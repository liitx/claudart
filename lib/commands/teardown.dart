import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../handoff_template.dart';
import '../md_io.dart';
import '../paths.dart';
import '../registry.dart';
import '../teardown_utils.dart';
import '../ui/menu.dart';

Future<void> runTeardown({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items)? pickFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final confirm_ = confirmFn ?? confirm;
  final prompt_ = promptFn ?? _defaultPrompt;
  final pick_ = pickFn ?? arrowMenu;

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

  // Extract session info upfront so we can pre-populate prompts.
  final bug = readSection(handoff, 'Bug');
  final rootCause = readSection(handoff, 'Root Cause');
  final debugProgress = extractSection(handoff, 'Debug Progress');
  final changedFiles = readSubSection(debugProgress, 'What changed (files modified)');
  final branch = extractBranch(handoff);

  // Show session summary before confirming.
  print('\n───────────────────────────────────────');
  print('  Bug     : ${_truncate(bug)}');
  print('  Cause   : ${_truncate(rootCause)}');
  if (!_isBlank(changedFiles)) {
    print('  Changed : ${_truncate(changedFiles)}');
  }
  print('  Branch  : $branch');
  print('───────────────────────────────────────\n');

  if (!confirm_('Is the bug confirmed resolved?')) {
    print('\nCome back when the fix is confirmed. Continue with /debug or /suggest.\n');
    exit_(0);
  }

  final fixSummary = prompt_('Briefly describe the fix (one or two sentences)');

  print('\n───────────────────────────────────────');
  print('Categorize this session for skills.md:');
  print('───────────────────────────────────────\n');

  final categoryChoice = pick_(_kCategories);
  final String category;
  if (categoryChoice == _kCategories.length - 1) {
    category = prompt_('Enter category') ?? 'general';
  } else {
    category = _kCategories[categoryChoice];
  }

  // Pre-populate hot files from "What changed" — user confirms or overrides.
  final hotFilesDefault = _isBlank(changedFiles) ? null : changedFiles.replaceAll('\n', ', ').trim();
  final hotFiles = _promptWithDefault(
    prompt_,
    'Which files were confirmed key to the fix?',
    hotFilesDefault,
  );

  final coldFiles = prompt_(
    'Any files explored but NOT the root cause? (comma-separated, or skip)',
    optional: true,
  );

  // Pre-populate pattern from root cause — user confirms or overrides.
  final patternDefault = _isBlank(rootCause) ? null : rootCause.replaceAll('\n', ' ').trim();
  final pattern = _promptWithDefault(
    prompt_,
    'Describe the root cause pattern generically (one sentence)',
    patternDefault,
  );

  final fixPattern = prompt_(
    'Describe the fix pattern generically (one sentence)\n  e.g. "Added restartable transformer to ensure sequential event processing"',
  );

  // Update skills.md.
  _updateSkills(
    fileIO: fileIO,
    skillsFile: skillsPathFor(workspace),
    branch: branch,
    category: category,
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

const List<String> _kCategories = [
  'api-mapping',
  'bloc-event-handling',
  'ffi-bridge',
  'general',
  'legacy-path-migration',
  'provider-state',
  'widget-lifecycle',
  'other (type manually)',
];

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);

String? _promptWithDefault(
  String? Function(String, {bool optional}) prompt_,
  String question,
  String? defaultValue,
) {
  if (defaultValue != null) {
    return prompt_(
          '$question\n  (press enter to use: "$defaultValue")',
          optional: true,
        ) ??
        defaultValue;
  }
  return prompt_(question);
}

bool _isBlank(String s) =>
    s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

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
