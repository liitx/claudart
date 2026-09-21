import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../templates/handoff_template.dart';
import '../md_io.dart';
import '../paths.dart';
import '../pipeline/flows/teardown_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../session/archive_entry.dart';
import '../session/run_mode.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../session/workspace_guard.dart';
import '../ui/menu.dart';
import '../util/prompt_with_default.dart';
import '../ui/render.dart' as render;
import '../ui/ansi.dart' as ansi;

Future<void> runTeardown({
  FileIO? io,
  String? projectRootOverride,
  RunMode mode = RunMode.interactive,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items, {int startIndex})? pickFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final headless = mode == RunMode.headless;
  // In headless mode nothing calls these — every decision below resolves
  // itself instead — but they're still constructed so the interactive
  // branches (kept verbatim) don't need every call site to check `headless`.
  final confirm_ = confirmFn ?? confirm;
  final prompt_ = promptFn ?? _defaultPrompt;
  final pick_ = pickFn ?? arrowMenu;

  print(render.header('CLAUDART SESSION TEARDOWN'));
  if (headless) {
    print('  ${ansi.dim}headless — every decision below resolves itself; verify the summary at the end${ansi.reset}\n');
  }

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
  print('Project  : ${entry.name}');

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
  print('\n${render.divider()}');
  print('  Bug     : ${_truncate(bug)}');
  print('  Cause   : ${_truncate(rootCause)}');
  if (!_isBlank(changedFiles)) {
    print('  Changed : ${_truncate(changedFiles)}');
  }
  print('  Branch  : $branch');
  print('${render.divider()}\n');

  // Headless resolves "confirmed resolved?" from the handoff's own typed
  // status rather than asking — debugComplete is the one HandoffStatus
  // variant that means "fix verified" per the FSA (docs/design.md). Any
  // other status headless treats the same way a human declining the
  // interactive confirm would: save as a reminder, don't archive as fixed.
  final resolved = headless
      ? SessionState.parse(handoff).status == HandoffStatus.debugComplete
      : confirm_('Is the bug confirmed resolved?');

  if (!resolved) {
    // Offer to save as a reminder so the session can be resumed later.
    // Headless always saves the reminder — there's no human to decline it
    // for, and silently discarding an unresolved session's context would
    // lose exactly the state teardown exists to preserve.
    if (headless || confirm_('Save as a reminder to resume later?')) {
      final description = headless
          ? bug
          : prompt_("Brief description (what's still pending)", optional: true) ?? '';
      final resolvedDescription =
          description.trim().isEmpty ? bug : description.trim();
      if (headless) {
        // Same "verify before trusting the archive" contract as the
        // resolved path's fuller Headless decisions block below — this
        // write happens with no human prompt too, so what's about to be
        // archived must be visible first, not just discoverable after.
        print('\n${render.divider()}');
        print('Headless decision — verify before trusting the archive:');
        print(render.divider());
        print('  Record type : reminder (not confirmed resolved)');
        print('  Description : ${_truncate(resolvedDescription)}');
        print(render.divider());
      }
      writeArchiveEntry(
        workspace:   workspace,
        branch:      branch,
        handoff:     handoff,
        kind:        ArchiveKind.reminder,
        description: resolvedDescription,
        io:          fileIO,
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

  final analyzerOut           = analyzerCtx[TeardownSteps.slotKey] ?? '';
  final agentCategory  = tagOrNull(analyzerOut, 'CATEGORY')           ?? '';
  final agentSummary   = tagOrNull(analyzerOut, 'FIX_SUMMARY')        ?? '';
  final agentHotFiles  = tagOrNull(analyzerOut, 'HOT_FILES');
  final agentColdFiles = tagOrNull(analyzerOut, 'COLD_FILES');
  final agentRootPat   = tagOrNull(analyzerOut, 'ROOT_CAUSE_PATTERN') ?? '';
  final agentFixPat    = tagOrNull(analyzerOut, 'FIX_PATTERN')        ?? '';

  // ── Archive kind ─────────────────────────────────────────────────────────────
  //
  // Reaching this point already means resolved == true (the unresolved
  // branch above always exits) — headless always archives here, the same
  // outcome the interactive default (index 0) represents.

  final ArchiveKind archiveKind;
  if (headless) {
    archiveKind = ArchiveKind.archive;
  } else {
    print('\n${render.divider()}');
    print('Session record type:');
    print('${render.divider()}\n');
    final kindChoice = pick_(['archive (resolved — skills updated)', 'reminder (note for future reference)']);
    archiveKind = kindChoice == 1 ? ArchiveKind.reminder : ArchiveKind.archive;
  }

  // ── Fix summary (agent pre-filled) ───────────────────────────────────────────

  final fixSummary = headless
      ? (agentSummary.isEmpty ? 'Fix for: ${_truncate(bug)}' : agentSummary)
      : promptWithDefault(
          prompt_,
          'Briefly describe the fix (one or two sentences)',
          agentSummary.isEmpty ? null : agentSummary,
        );

  // ── Category (agent pre-selected in menu) ────────────────────────────────────

  final suggestedIdx = TeardownCategory.values.indexWhere((c) => c.value == agentCategory);
  final startIdx     = suggestedIdx >= 0 ? suggestedIdx : TeardownCategory.values.indexOf(TeardownCategory.general);
  final String category;
  final String area;
  if (headless) {
    // Headless never lands on `other` — that variant exists specifically
    // for a human typing a category the fixed list doesn't cover.
    final cat = TeardownCategory.values[startIdx];
    category = cat.value;
    area = cat.area;
  } else {
    print('\nCategorize this session for skills.md:');
    final categoryChoice = pick_(_kCategories, startIndex: startIdx);
    final cat            = TeardownCategory.values[categoryChoice];
    if (cat == TeardownCategory.other) {
      final raw = prompt_('Enter category') ?? '';
      category = raw.trim().isEmpty ? 'general' : raw.trim();
      area = 'fix';
    } else {
      category = cat.value;
      area = cat.area;
    }
  }

  // ── Hot / cold files (agent pre-filled) ──────────────────────────────────────

  final hotFilesDefault = agentHotFiles?.isNotEmpty == true
      ? agentHotFiles
      : (_isBlank(changedFiles) ? null : changedFiles.replaceAll('\n', ', ').trim());
  final hotFiles = headless
      ? hotFilesDefault
      : promptWithDefault(
          prompt_,
          'Which files were confirmed key to the fix?',
          hotFilesDefault,
        );

  final coldDefault = agentColdFiles?.toLowerCase() == 'none' ? null : agentColdFiles;
  final coldFiles   = headless
      ? coldDefault
      : promptWithDefault(
          prompt_,
          'Any files explored but NOT the root cause? (comma-separated, or skip)',
          coldDefault,
          optional: true,
        );

  // ── Root cause / fix pattern (agent pre-filled) ───────────────────────────────

  final patternDefault = agentRootPat.isNotEmpty
      ? agentRootPat
      : (_isBlank(rootCause) ? null : rootCause.replaceAll('\n', ' ').trim());
  final pattern = headless
      ? (patternDefault ?? 'unspecified')
      : promptWithDefault(
          prompt_,
          'Describe the root cause pattern generically (one sentence)',
          patternDefault,
        );

  final fixPattern = headless
      ? (agentFixPat.isEmpty ? fixSummary : agentFixPat)
      : promptWithDefault(
          prompt_,
          'Describe the fix pattern generically (one sentence)',
          agentFixPat.isEmpty ? null : agentFixPat,
        );

  if (headless) {
    print('\n${render.divider()}');
    print('Headless decisions — verify before trusting the archive:');
    print(render.divider());
    print('  Record type : ${archiveKind == ArchiveKind.archive ? 'archive (resolved)' : 'reminder'}');
    print('  Category    : $category');
    print('  Fix summary : $fixSummary');
    print('  Hot files   : ${hotFiles ?? 'unspecified'}');
    print('  Cold files  : ${coldFiles ?? '(none)'}');
    print('  Root cause  : $pattern');
    print('  Fix pattern : $fixPattern');
    print(render.divider());
  }

  // Update skills.md, archive the handoff, and reset it — guarded so an
  // interrupted run leaves the workspace.lock signal instead of a half
  // updated skills.md / archive, same as `kill`.
  late final String archiveFile;
  try {
    await withGuard(workspace, 'teardown', () async {
      // A reminder is a note for later, not a resolved fix — no skills
      // update, matching ArchiveKind.reminder's documented "no skills update".
      if (archiveKind != ArchiveKind.reminder) {
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
      }

      // A resolved, archived session's root cause is now promoted to Root
      // Cause Patterns above — its Pending entry (written by /save) would
      // otherwise sit there stale forever. A reminder is not a real
      // resolution, so its Pending entry stays.
      if (archiveKind == ArchiveKind.archive) {
        final skillsFile = skillsPathFor(workspace);
        final skills = fileIO.fileExists(skillsFile) ? fileIO.read(skillsFile) : '';
        fileIO.write(skillsFile, removePendingEntry(skills, branch));
      }

      final entry = writeArchiveEntry(
        workspace:   workspace,
        branch:      branch,
        handoff:     handoff,
        kind:        archiveKind,
        description: fixSummary ?? bug,
        io:          fileIO,
        skillsDelta: archiveKind == ArchiveKind.archive
            ? '$category: $pattern → $fixPattern'
            : null,
      );
      archiveFile = p.join(archiveDirFor(workspace), entry.handoffFile);

      // Reset handoff.
      fileIO.write(handoffFile, blankHandoff);
    }, io: fileIO);
  } on WorkspaceLockedException catch (e) {
    print('\n✗ ${e.toString()}\n');
    exit_(1);
  }

  // Suggest commit message.
  final commitMsg = buildCommitMessage(area, bug, rootCause, fixSummary!);

  if (archiveKind != ArchiveKind.reminder) {
    print('\n✓ Skills updated: ${skillsPathFor(workspace)}');
  }
  print('✓ Handoff archived: $archiveFile');
  print('✓ Handoff reset.\n');
  print(render.divider());
  print('Suggested commit message:\n');
  print(commitMsg);
  print(render.divider());
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
        general || other => 'fix',
      };

  /// Display label shown in the interactive menu.
  String get label => this == other ? 'other (type manually)' : value;
}

List<String> get _kCategories =>
    TeardownCategory.values.map((c) => c.label).toList();

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);


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

