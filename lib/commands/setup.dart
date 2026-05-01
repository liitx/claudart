import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../handoff_template.dart';
import '../md_io.dart';
import '../paths.dart';
import '../registry.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';
import '../sensitivity/token_map.dart';
import '../logging/logger.dart';
import '../session/session_state.dart' show SessionState, HandoffStatus;
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import 'scan.dart';

/// Returns absolute paths of files named [basename] under [projectRoot].
/// Injectable for tests — default uses the OS `find` command.
typedef FileFinderFn = List<String> Function(String projectRoot, String basename);

Future<void> runSetup({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items)? pickFn,
  Never Function(int code)? exitFn,
  FileFinderFn? fileFinderFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final confirm_ = confirmFn ?? confirm;
  final prompt_ = promptFn ?? _defaultPrompt;
  final pick_ = pickFn ?? arrowMenu;
  final finder_ = fileFinderFn ?? _defaultFileFinder;

  print('\n═══════════════════════════════════════');
  print('  CLAUDART SESSION SETUP');
  print('═══════════════════════════════════════');

  // Resolve project root.
  final gitCtx = projectRootOverride != null ? null : detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;

  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project root.');
    exit_(1);
  }

  if (!fileIO.dirExists(projectRoot)) {
    print('\n✗ Path not found: $projectRoot');
    exit_(1);
  }

  // Registry lookup.
  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('\n✗ No claudart session found for this project.');
    print('  Run `claudart link` to register it first.');
    exit_(1);
  }

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);

  // Check for active handoff — offer menu if one exists with real content.
  final existing =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';
  if (existing.isNotEmpty) {
    final state = SessionState.parse(existing);
    if (state.hasActiveContent) {
      final statusColour = _statusColour(state.status);
      print('\n─── ${entry.name} ───────────────────────────────');
      print('  Branch : ${state.branch}');
      print('  Status : ${ansi.c(statusColour, state.status.value)}');
      print('  Bug    : ${_truncate(state.bug)}');
      print('');

      final choice = pick_([
        '${ansi.c(ansi.green, 'Continue')}  resume existing session',
        '${ansi.c(ansi.yellow, 'Start fresh')}  overwrite handoff with new context',
        'Back',
      ]);

      if (choice == _SetupMenu.back) {
        print('\nSetup cancelled.\n');
        exit_(0);
      }
      if (choice == _SetupMenu.resume) {
        print('\nOpen your editor and run /suggest or /debug to continue.\n');
        exit_(0);
      }
      assert(choice == _SetupMenu.startFresh);
      // Fall through to questions below.
    }
  }

  // Detect branch — use git context already resolved, or fall back to prompt.
  final branch = gitCtx?.branch ??
      prompt_('Could not detect git branch. Enter branch name manually') ??
      'unknown';

  print('\n🌿 Branch: $branch');

  // Surface skills context.
  final skillsFile = skillsPathFor(workspace);
  final skills =
      fileIO.fileExists(skillsFile) ? fileIO.read(skillsFile) : '';
  if (skills.isNotEmpty && !skills.contains('_No sessions recorded yet._')) {
    print('\n📚 Skills loaded — relevant patterns will inform /suggest.');
  }

  // Prompt for session context.
  print('\nAnswer the following. Be specific — this seeds the handoff for /suggest.\n');

  final bug = prompt_('1. What is the bug? (actual behavior)');
  final expected = prompt_('2. What should be happening? (expected behavior)');

  if (bug == null || expected == null) {
    print('\n✗ Setup requires an interactive terminal.');
    exit_(1);
  }

  final files = prompt_('3. Any files already in mind?', optional: true);
  final entryPoints = prompt_(
    '4. Any functions, classes, or entry points involved?',
    optional: true,
  );

  // Confirm before writing.
  print('\n───────────────────────────────────────');
  print('Project : ${entry.name}');
  print('Branch  : $branch');
  print('Bug     : $bug');
  print('Expected: $expected');
  if (files != null) print('Files   : $files');
  if (entryPoints != null) print('Entry   : $entryPoints');
  print('───────────────────────────────────────');

  if (!confirm_('Write handoff with this context?')) {
    print('\nSetup cancelled.');
    exit_(0);
  }

  // Run sensitivity scan if enabled.
  if (entry.sensitivityMode) {
    await runScan(scope: null, projectRootOverride: projectRoot, workspacePath: workspace);
  }

  // Build handoff content.
  final date = DateTime.now().toIso8601String().split('T').first;
  var content = handoffTemplate(
    branch: branch,
    date: date,
    bug: bug,
    expected: expected,
    projectName: entry.name,
    files: files != null ? _resolveFilePaths(files, projectRoot, finder_) : null,
    entryPoints: entryPoints,
  );

  // Abstract sensitive tokens if sensitivity mode on.
  if (entry.sensitivityMode) {
    final tokenMap = TokenMap.load(tokenMapPathFor(workspace));
    content = abstractor.abstract(content, tokenMap, defaultDetector);
    if (!abstractor.isNotSensitive(content, defaultDetector)) {
      print('\n⚠  Handoff still contains sensitive tokens after abstraction.');
      print('   Review handoff.md manually before sharing.');
    }
  }

  fileIO.write(handoffFile, content);

  // Log the setup interaction.
  final logger = SessionLogger(io: fileIO, sensitivityMode: entry.sensitivityMode, workspacePath: workspace);
  logger.logInteraction(
    command: 'setup',
    outcome: 'ok',
    platform: Platform.operatingSystem,
  );

  print('\n✓ Handoff written to $handoffFile');
  print('\nNext step:');
  print('  Open your editor and run /suggest to begin exploration.');
  print('  Or run /debug if you already know the root cause.\n');
}

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);

abstract final class _SetupMenu {
  static const resume = 0;
  static const startFresh = 1; // fall-through: proceeds to questions
  static const back = 2;
}

String _statusColour(HandoffStatus s) => switch (s) {
      HandoffStatus.suggestInvestigating ||
      HandoffStatus.readyForSuggest      => ansi.cyan,
      HandoffStatus.readyForDebug        => ansi.yellow,
      HandoffStatus.debugInProgress ||
      HandoffStatus.debugComplete        => ansi.green,
      HandoffStatus.needsSuggest         => ansi.red,
      HandoffStatus.unknown ||
      HandoffStatus.noHandoff            => ansi.dim,
    };

String _truncate(String s, {int max = 60}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

// ── File resolution ───────────────────────────────────────────────────────────

sealed class _FileResolution {
  const _FileResolution();
}

final class _Resolved extends _FileResolution {
  const _Resolved(this.relativePaths);
  final List<String> relativePaths; // one entry = unique; many = ambiguous
}

final class _NotFound extends _FileResolution {
  const _NotFound(this.token);
  final String token;
}

/// Default [FileFinderFn] — delegates to the OS `find` command, skipping
/// hidden dirs and common build artefacts.
List<String> _defaultFileFinder(String projectRoot, String basename) {
  final result = Process.runSync(
    'find',
    [projectRoot, '-type', 'f', '-name', basename,
     '!', '-path', '*/.dart_tool/*',
     '!', '-path', '*/.git/*',
     '!', '-path', '*/build/*',
    ],
  );
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Resolves a single [token] to a [_FileResolution] using [finder].
_FileResolution _resolveToken(
  String token,
  String projectRoot,
  FileFinderFn finder,
) {
  final paths = finder(projectRoot, p.basename(token))
      .map((abs) => p.relative(abs, from: projectRoot))
      .toList();

  return paths.isEmpty ? _NotFound(token) : _Resolved(paths);
}

/// Converts raw user file input into the backtick-formatted list that
/// `parseScopeFiles` expects.
///
///   "contact_sxm_page.dart, foo.dart"
///   → "- `ivi/…/contact_sxm_page.dart` — (user-provided)"
String _resolveFilePaths(String raw, String projectRoot, FileFinderFn finder) {
  final tokens = raw
      .split(RegExp(r'[,\n]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty);

  return tokens.expand((token) {
    return switch (_resolveToken(token, projectRoot, finder)) {
      _Resolved(:final relativePaths) =>
        relativePaths.map((rel) => '- `$rel` — (user-provided)'),
      _NotFound(:final token) =>
        ['- `$token` — (not found — verify path)'],
    };
  }).join('\n');
}
