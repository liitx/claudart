import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../handoff_template.dart';
import '../md_io.dart';
import '../paths.dart';
import '../registry.dart';
import '../teardown_utils.dart';

Future<void> runTeardown({
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
  print('  CLAUDART SESSION TEARDOWN');
  print('═══════════════════════════════════════');

  final gitCtx = projectRootOverride != null ? null : detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;

  if (projectRoot == null) {
    print('✗ Not inside a git repository. Cannot detect project.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('✗ No claudart session found for this project.');
    print('  Run `claudart link` to register it.');
    exit_(1);
  }

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final handoff =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';

  if (handoff.isEmpty) {
    print('\nNo active handoff found. Nothing to tear down.\n');
    exit_(0);
  }

  if (!confirm_('Is the bug confirmed resolved?')) {
    print('\nCome back when the fix is confirmed. Continue with /debug or /suggest.\n');
    exit_(0);
  }

  final fixSummary = prompt_('Briefly describe the fix (one or two sentences)');

  // Extract session info.
  final bug = readSection(handoff, 'Bug');
  final rootCause = readSection(handoff, 'Root Cause');
  final debugProgress = extractSection(handoff, 'Debug Progress');
  readSubSection(debugProgress, 'What changed (files modified)');
  final branch = extractBranch(handoff);

  print('\n───────────────────────────────────────');
  print('Extracting learnings from session...');
  print('───────────────────────────────────────');
  print('\nHelp categorize this session for skills.md:\n');

  final category = prompt_(
    'Root cause category?\n  (e.g. bloc-event-handling / provider-state / api-mapping / widget-lifecycle / ffi-bridge)',
  );

  final hotFiles = prompt_(
    'Which files were confirmed key to the fix? (comma-separated, or "none")',
    optional: true,
  );

  final coldFiles = prompt_(
    'Any files explored but NOT the root cause? (comma-separated, or skip)',
    optional: true,
  );

  final pattern = prompt_(
    'Describe the root cause pattern generically (one sentence)\n  e.g. "BLoC emits stale state when event fires before previous async resolves"',
  );

  final fixPattern = prompt_(
    'Describe the fix pattern generically (one sentence)\n  e.g. "Added restartable transformer to ensure sequential event processing"',
  );

  // Update skills.md.
  _updateSkills(
    fileIO: fileIO,
    skillsFile: skillsPathFor(workspace),
    branch: branch,
    category: category!,
    hotFiles: hotFiles,
    coldFiles: coldFiles,
    pattern: pattern!,
    fixPattern: fixPattern!,
  );

  // Archive handoff.
  final archiveDirectory = archiveDirFor(workspace);
  final archiveFile = p.join(archiveDirectory, archiveName(branch));
  fileIO.createDir(archiveDirectory);
  fileIO.write(archiveFile, handoff);

  // Reset handoff.
  fileIO.write(handoffFile, blankHandoff);

  // Suggest commit message.
  final area = areaFromCategory(category);
  final commitMsg = buildCommitMessage(area, bug, rootCause, fixSummary!);

  print('\n✓ Skills updated: ${skillsPathFor(workspace)}');
  print('✓ Handoff archived: $archiveFile');
  print('✓ Handoff reset.\n');
  print('───────────────────────────────────────');
  print('Suggested commit message:\n');
  print(commitMsg);
  print('───────────────────────────────────────');
  print('\nRemember: do not push to remote. Open a merge request from your branch.\n');
}

void _updateSkills({
  required FileIO fileIO,
  required String skillsFile,
  required String branch,
  required String category,
  String? hotFiles,
  String? coldFiles,
  required String pattern,
  required String fixPattern,
}) {
  var skills =
      fileIO.fileExists(skillsFile) ? fileIO.read(skillsFile) : _defaultSkillsTemplate();

  final date = DateTime.now().toIso8601String().split('T').first;

  skills = appendToSection(
      skills, 'Root Cause Patterns', '- **$category**: $pattern → Fix: $fixPattern');

  if (hotFiles != null && hotFiles.toLowerCase() != 'none') {
    for (final file
        in hotFiles.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty)) {
      skills = incrementHotPath(skills, category, file);
    }
  }

  if (coldFiles != null && coldFiles.toLowerCase() != 'none') {
    for (final file
        in coldFiles.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty)) {
      skills = appendToSection(skills, 'Anti-patterns',
          '- `$file` — explored for $category, not the root cause');
    }
  }

  if (branch != 'unknown') {
    skills = appendToSection(
        skills, 'Branch Notes', '- `$branch` ($date): $category resolved');
  }

  skills = appendToSection(
      skills, 'Session Index', '`$branch` | $date | $category | resolved');

  fileIO.write(skillsFile, skills);
}

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);

String _defaultSkillsTemplate() => '''# Accumulated Skills

> Updated by `claudart teardown` after each resolved session.
> Read by `/suggest` and `/debug` at the start of every session.

---

## Hot Paths

_No sessions recorded yet._

---

## Root Cause Patterns

_No patterns recorded yet._

---

## Anti-patterns

_None recorded yet._

---

## Branch Notes

_None recorded yet._

---

## Session Index

_No sessions recorded yet._
''';
