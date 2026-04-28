import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../handoff_template.dart';
import '../md_io.dart';
import '../paths.dart';
import '../pipeline/flows/teardown_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../session/archive_entry.dart';
import '../teardown_utils.dart';
import '../ui/menu.dart';
import '../workspace/workspace_index.dart';

Future<void> runTeardown({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items, {int startIndex})? pickFn,
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
    // Offer to save as a reminder so the session can be resumed later.
    if (confirm_('Save as a reminder to resume later?')) {
      final description = prompt_("Brief description (what's still pending)", optional: true) ?? '';
      _writeArchiveEntry(
        fileIO:      fileIO,
        workspace:   workspace,
        kind:        ArchiveKind.reminder,
        description: description.trim().isEmpty ? bug : description.trim(),
        branch:      branch,
        handoff:     handoff,
        skillsDelta: null,
      );
      print('\n✓ Reminder saved. Run `claudart archives` to resume.\n');
    }
    print('\nCome back when the fix is confirmed. Continue with /debug or /suggest.\n');
    exit_(0);
  }

  // ── Run teardown analyzer (haiku) to pre-fill all metadata ─────────────────

  print('');
  final analyzerCtx = await PipelineExecutor().runFuture(
    steps:        [TeardownSteps.analyzer],
    ctx:          PipelineContext(
      projectRoot: projectRoot,
      bug:         handoff,
      expected:    '',
      files:       [],
    ),
    displayStep:  1,
    displayTotal: 1,
  );

  final _out           = analyzerCtx[TeardownSteps.slotKey] ?? '';
  final agentCategory  = tagOrNull(_out, 'CATEGORY')           ?? '';
  final agentSummary   = tagOrNull(_out, 'FIX_SUMMARY')        ?? '';
  final agentHotFiles  = tagOrNull(_out, 'HOT_FILES');
  final agentColdFiles = tagOrNull(_out, 'COLD_FILES');
  final agentRootPat   = tagOrNull(_out, 'ROOT_CAUSE_PATTERN') ?? '';
  final agentFixPat    = tagOrNull(_out, 'FIX_PATTERN')        ?? '';

  // ── Archive kind ─────────────────────────────────────────────────────────────

  print('\n───────────────────────────────────────');
  print('Session record type:');
  print('───────────────────────────────────────\n');
  final kindChoice  = pick_(['archive (resolved — skills updated)', 'reminder (note for future reference)']);
  final archiveKind = kindChoice == 1 ? ArchiveKind.reminder : ArchiveKind.archive;

  // ── Fix summary (agent pre-filled) ───────────────────────────────────────────

  final fixSummary = _promptWithDefault(
    prompt_,
    'Briefly describe the fix (one or two sentences)',
    agentSummary.isEmpty ? null : agentSummary,
  );

  // ── Category (agent pre-selected in menu) ────────────────────────────────────

  print('\n───────────────────────────────────────');
  print('Categorize this session for skills.md:');
  print('───────────────────────────────────────\n');

  final suggestedIdx   = TeardownCategory.values.indexWhere((c) => c.value == agentCategory);
  final startIdx       = suggestedIdx >= 0 ? suggestedIdx : TeardownCategory.values.indexOf(TeardownCategory.general);
  final categoryChoice = pick_(_kCategories, startIndex: startIdx);
  final cat            = TeardownCategory.values[categoryChoice];
  final String category;
  final String area;
  if (cat == TeardownCategory.other) {
    final raw = prompt_('Enter category') ?? '';
    category = raw.trim().isEmpty ? 'general' : raw.trim();
    area = 'fix';
  } else {
    category = cat.value;
    area = cat.area;
  }

  // ── Hot / cold files (agent pre-filled) ──────────────────────────────────────

  final hotFilesDefault = agentHotFiles?.isNotEmpty == true
      ? agentHotFiles
      : (_isBlank(changedFiles) ? null : changedFiles.replaceAll('\n', ', ').trim());
  final hotFiles = _promptWithDefault(
    prompt_,
    'Which files were confirmed key to the fix?',
    hotFilesDefault,
  );

  final coldDefault = agentColdFiles?.toLowerCase() == 'none' ? null : agentColdFiles;
  final coldFiles   = _promptWithDefault(
    prompt_,
    'Any files explored but NOT the root cause? (comma-separated, or skip)',
    coldDefault,
    optional: true,
  );

  // ── Root cause / fix pattern (agent pre-filled) ───────────────────────────────

  final patternDefault = agentRootPat.isNotEmpty
      ? agentRootPat
      : (_isBlank(rootCause) ? null : rootCause.replaceAll('\n', ' ').trim());
  final pattern = _promptWithDefault(
    prompt_,
    'Describe the root cause pattern generically (one sentence)',
    patternDefault,
  );

  final fixPattern = _promptWithDefault(
    prompt_,
    'Describe the fix pattern generically (one sentence)',
    agentFixPat.isEmpty ? null : agentFixPat,
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

  // Archive handoff + write index entry.
  final archiveDirectory  = archiveDirFor(workspace);
  final archiveFileName   = archiveName(branch);
  final archiveFile       = p.join(archiveDirectory, archiveFileName);
  fileIO.createDir(archiveDirectory);
  fileIO.write(archiveFile, handoff);
  _writeArchiveEntry(
    fileIO:          fileIO,
    workspace:       workspace,
    kind:            archiveKind,
    description:     fixSummary ?? bug,
    branch:          branch,
    handoff:         handoff,
    handoffFileName: archiveFileName,
    skillsDelta:     archiveKind == ArchiveKind.archive
        ? '$category: $pattern → $fixPattern'
        : null,
  );

  // Reset handoff.
  fileIO.write(handoffFile, blankHandoff);

  // Suggest commit message.
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

enum TeardownCategory {
  apiIntegration,
  concurrency,
  configuration,
  dataParsing,
  ioFilesystem,
  stateManagement,
  general,
  other;

  /// Canonical string written to skills.md.
  String get value => switch (this) {
        apiIntegration  => 'api-integration',
        concurrency     => 'concurrency',
        configuration   => 'configuration',
        dataParsing     => 'data-parsing',
        ioFilesystem    => 'io-filesystem',
        stateManagement => 'state-management',
        general         => 'general',
        other           => 'other',
      };

  /// Commit area label for buildCommitMessage.
  String get area => switch (this) {
        apiIntegration  => 'api',
        concurrency     => 'async',
        configuration   => 'config',
        ioFilesystem    => 'io',
        stateManagement => 'state',
        dataParsing     => 'data',
        general         => 'fix',
        other           => 'fix',
      };

  /// Display label shown in the interactive menu.
  String get label => this == other ? 'other (type manually)' : value;
}

List<String> get _kCategories =>
    TeardownCategory.values.map((c) => c.label).toList();

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);

String? _promptWithDefault(
  String? Function(String, {bool optional}) prompt_,
  String question,
  String? defaultValue, {
  bool optional = false,
}) {
  if (defaultValue != null) {
    return prompt_(
          '$question\n  (press enter to use: "$defaultValue")',
          optional: true,
        ) ??
        defaultValue;
  }
  return prompt_(question, optional: optional);
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

void _writeArchiveEntry({
  required FileIO      fileIO,
  required String      workspace,
  required ArchiveKind kind,
  required String      description,
  required String      branch,
  required String      handoff,
  String?              handoffFileName,
  String?              skillsDelta,
}) {
  final ts       = DateTime.now();
  final fileName = handoffFileName ?? archiveName(branch);
  // Ensure the handoff file exists (reminder path may not have written it yet).
  if (handoffFileName == null) {
    final dir = archiveDirFor(workspace);
    fileIO.createDir(dir);
    fileIO.write('$dir/$fileName', handoff);
  }
  final entry = ArchiveEntry(
    id:          '${branch}_${ts.millisecondsSinceEpoch}',
    kind:        kind,
    description: description,
    branch:      branch,
    createdAt:   ts,
    handoffFile: fileName,
    skillsDelta: skillsDelta,
  );
  appendToIndex(workspace, entry, io: fileIO);
}
