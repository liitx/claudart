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
import 'scan.dart';

Future<void> runSetup({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final confirm_ = confirmFn ?? confirm;
  final prompt_ = promptFn ?? _defaultPrompt;

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

  // Check for active handoff.
  final existing =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';
  if (existing.isNotEmpty) {
    final status = readStatus(existing);
    if (status != 'suggest-investigating' &&
        !existing.contains('_Not yet determined._\n\n---\n\n## Expected')) {
      print('\n⚠  Active handoff found (status: $status)');
      if (!confirm_('Overwrite and start a new session?')) {
        print('\nSetup cancelled. Run /suggest or /debug to continue the existing session.');
        exit_(0);
      }
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
  final files = prompt_('3. Any files already in mind?', optional: true);
  final blocs = prompt_(
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
  if (blocs != null) print('BLoCs   : $blocs');
  print('───────────────────────────────────────');

  if (!confirm_('Write handoff with this context?')) {
    print('\nSetup cancelled.');
    exit_(0);
  }

  // Run sensitivity scan if enabled.
  // TODO: migrate scan.dart to accept workspace path instead of using claudeDir.
  if (entry.sensitivityMode) {
    await runScan(scope: null, projectRootOverride: projectRoot);
  }

  // Build handoff content.
  final date = DateTime.now().toIso8601String().split('T').first;
  var content = handoffTemplate(
    branch: branch,
    date: date,
    bug: bug!,
    expected: expected!,
    projectName: entry.name,
    files: files,
    blocs: blocs,
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
  // TODO: migrate SessionLogger to accept workspace path instead of claudeDir.
  final logger = SessionLogger(sensitivityMode: entry.sensitivityMode);
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
