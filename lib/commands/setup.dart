import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../io/git_utils.dart';
import '../templates/handoff_template.dart';
import '../session/md_io.dart';
import '../config/paths.dart';
import '../registry.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';
import '../logging/logger.dart';
import '../session/handoff_event.dart';
import '../ui/menu.dart';
import 'support/claudart_command.dart';
import 'scan.dart';
import '../ui/render.dart' as render;
import '../util/prompt_with_default.dart';
import '../io/process_runner.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../session/handoff_store.dart';
import '../io/process_exit.dart';
import 'support/live_handoff.dart';
import '../io/exit_reason.dart';

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
  String? defaultBug,
  String? defaultExpected,
  String? defaultFiles,
  String? defaultEntryPoints,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exitProcess;
  final confirm_ = confirmFn ?? confirm;
  final prompt_ = promptFn ?? _defaultPrompt;
  final pick_ = pickFn ?? arrowMenu;
  final finder_ = fileFinderFn ?? _defaultFileFinder;

  print(render.header('CLAUDART SESSION SETUP'));

  // Resolve project root.
  final gitCtx = detectGitContext(workingDirectory: projectRootOverride);
  final projectRoot = projectRootOverride ?? gitCtx?.root;

  if (projectRoot == null) {
    print(UserText.notInGitRepositoryRoot.template.trimRight());
    leaveFor(ExitReason.setupNotInGitRepository, exit_: exit_);
  }

  if (!fileIO.dirExists(projectRoot)) {
    print(UserText.setupPathNotFound.format({'projectRoot': projectRoot}));
    leaveFor(ExitReason.setupPathNotFound, exit_: exit_);
  }

  // Registry lookup.
  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print(UserText.setupNoClaudartSessionFoundForThis.template);
    print(UserText.setupRunClaudartLinkToRegisterIt.template);
    leaveFor(ExitReason.setupNotLinked, exit_: exit_);
  }
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);

  // A live handoff is settled first: continue it, start fresh (archiving it),
  // or go back. The status this setup starts from is none when there is no
  // live handoff, or the one a "Start fresh" replaced.
  final startedFrom = settleLiveHandoff(
    io: fileIO,
    entry: entry,
    gitBranch: gitCtx?.branch,
    pick: pick_,
    exit_: exit_,
    resumeText: UserText.setupOpenYourEditorAndRunSuggest,
    cancelledText: UserText.setupSetupCancelled,
  );

  // Detect branch — use git context already resolved, or fall back to prompt.
  final branch = gitCtx?.branch ??
      prompt_('Could not detect git branch. Enter branch name manually') ??
      'unknown';

  print(UserText.setupBranch.format({'branch': branch}));

  // Surface skills context.
  final skillsFile = skillsPathFor(workspace);
  final skills =
      fileIO.fileExists(skillsFile) ? fileIO.read(skillsFile) : '';
  if (skills.isNotEmpty && !skills.contains('_No sessions recorded yet._')) {
    print(UserText.setupSkillsLoadedRelevantPatternsWillInform.template);
  }

  // Prompt for session context.
  print(UserText.setupAnswerTheFollowingBeSpecificThis.template);

  final bug = promptWithDefault(prompt_, '1. What is the bug? (actual behavior)', defaultBug);
  final expected = promptWithDefault(
      prompt_, '2. What should be happening? (expected behavior)', defaultExpected);

  if (bug == null || expected == null) {
    print(UserText.setupSetupRequiresAnInteractiveTerminal.template);
    leaveFor(ExitReason.setupNeedsTerminal, exit_: exit_);
  }

  final files = promptWithDefault(prompt_, '3. Any files already in mind?', defaultFiles,
      optional: true);
  final entryPoints = promptWithDefault(
    prompt_,
    '4. Any functions, classes, or entry points involved?',
    defaultEntryPoints,
    optional: true,
  );

  // Confirm before writing.
  print('\n${render.divider()}');
  print(UserText.setupProject.format({'name': entry.name}));
  print(UserText.branchLine.format({'branch': branch}));
  print(UserText.setupBug.format({'bug': bug}));
  print(UserText.setupExpected.format({'expected': expected}));
  if (files != null) print(UserText.setupFiles.format({'files': files}));
  if (entryPoints != null) print(UserText.setupEntry.format({'entryPoints': entryPoints}));
  print(render.divider());

  if (!confirm_('Write handoff with this context?')) {
    print(UserText.setupCancelledLeadingBlank.template);
    leaveFor(ExitReason.setupCancelled, exit_: exit_);
  }

  // Run sensitivity scan if enabled.
  if (entry.sensitivityMode) {
    await runScan(
      io: fileIO,
      scope: null,
      projectRootOverride: projectRoot,
      sensitivityModeOverride: entry.sensitivityMode,
      workspacePath: workspace,
    );
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
    content = abstractTexts(
      [content],
      tokenMapPath: tokenMapPathFor(workspace),
      io: fileIO,
    ).single;
    if (!abstractor.isNotSensitive(content, defaultDetector)) {
      print(UserText.setupHandoffStillContainsSensitiveTokensAfter.template);
      print(UserText.setupReviewHandoffMdManuallyBeforeSharing.template);
    }
  }

  // Not enforced: "Start fresh" over a live handoff is allowed today, so a
  // status the table lacks is logged as a move it lacks rather than thrown.
  final logger = SessionLogger.forEntry(entry, io: fileIO);
  HandoffStore(
    io: fileIO,
    handoffFile: handoffFile,
    logger: logger,
    command: ClaudartCommand.setup.name,
  ).replace(content, from: startedFrom, event: HandoffEvent.setup);

  // Log the setup interaction.
  logger.logInteraction(
    rowKind: InteractionRowKind.outcome,
    command: 'setup',
    outcome: 'ok',
    platform: Platform.operatingSystem,
  );
  print(UserText.setupHandoffWrittenTo.format({'handoffFile': handoffFile}));
  print(UserText.nextStepHeading.template);
  print(UserText.setupOpenEditorRunSuggestToExplore.template);
  print(UserText.setupOrRunDebugIfYouAlready.template);
}

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);



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
  final result = const RealProcessRunner().runSync(
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

  // A Set keeps first-seen order and drops repeats, so typing the same file
  // twice (`calc.dart, lib/calc.dart` both resolve to one path) yields one bullet.
  return tokens.expand((token) {
    return switch (_resolveToken(token, projectRoot, finder)) {
      _Resolved(:final relativePaths) =>
        relativePaths.map((rel) => '- `$rel` — (user-provided)'),
      _NotFound(:final token) =>
        ['- `$token` — (not found — verify path)'],
    };
  }).toSet().join('\n');
}
