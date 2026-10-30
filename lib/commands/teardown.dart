import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../logging/logger.dart';
import 'support/claudart_command.dart';
import '../templates/handoff_template.dart';
import '../session/md_io.dart';
import '../config/paths.dart';
import '../pipeline/flows/teardown_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../session/debug_disposition.dart';
import '../session/handoff_placeholder.dart';
import '../session/knowledge_transfer.dart';
import '../session/archive_entry.dart';
import '../session/handoff_event.dart';
import '../session/run_mode.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../session/workspace_guard.dart';
import '../ui/menu.dart';
import '../util/prompt_with_default.dart';
import '../ui/render.dart' as render;
import 'support/project_resolution.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';
import '../ui/styled_text.dart';

/// The question `teardown` asks when a handoff is confirmed resolved but debug
/// did not run: debug must be recorded as skipped on purpose, never assumed.
const String kTeardownSkipDebugQuestion =
    'Debug did not run for this handoff. Record it as skipped?';

Future<void> runTeardown({
  FileIO? io,
  String? projectRootOverride,
  RunMode mode = RunMode.interactive,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items, {int startIndex})? pickFn,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
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
    print(UserText.teardownHeadlessEveryDecisionBelowResolvesItself.styled({}));
  }

  final project = requireProject(
    CommandSeams(
      io: fileIO,
      exitFn: exit_,
      projectRootOverride: projectRootOverride,
    ),
    withGitContext: true,
  );
  final projectRoot = project.projectRoot;
  final entry = project.entry;
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final handoff =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';

  if (handoff.isEmpty) {
    print(UserText.teardownNoActiveHandoffFoundNothingTo.template);
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
  print(UserText.teardownBug.format({'bug': _truncate(bug)}));
  print(UserText.teardownCause.format({'rootCause': _truncate(rootCause)}));
  if (!HandoffPlaceholder.isBlank(changedFiles)) {
    print(UserText.teardownChanged.format({'changedFiles': _truncate(changedFiles)}));
  }
  print(UserText.teardownBranch.format({'branch': branch}));
  print('${render.divider()}\n');

  // Headless resolves "confirmed resolved?" from the handoff's own typed
  // status rather than asking — debugComplete is the one HandoffStatus
  // variant that means "fix verified" per the FSA (docs/design.md). Any
  // other status headless treats the same way a human declining the
  // interactive confirm would: save as a reminder, don't archive as fixed.
  var resolved = headless
      ? SessionState.parse(handoff).status == HandoffStatus.debugComplete
      : confirm_('Is the bug confirmed resolved?');

  // A complete transfer that debug never finished is resolved only if debug is
  // recorded as skipped, so the decision is written into the archived handoff.
  var archivedHandoff = handoff;
  if (resolved && !headless) {
    final state = SessionState.parse(handoff);
    final debugNeverRan = state.effectiveStatus.knowledgeTransferExpectation ==
            KnowledgeTransferExpectation.converged &&
        state.debugDisposition == DebugDisposition.pending;
    if (debugNeverRan) {
      resolved = confirm_(kTeardownSkipDebugQuestion);
      if (resolved) {
        archivedHandoff =
            withDebugDisposition(handoff, DebugDisposition.skipped);
      }
    }
  }

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
        print(UserText.teardownHeadlessDecisionVerifyBeforeTrustingThe.template);
        print(render.divider());
        print(UserText.teardownRecordTypeReminderNotConfirmedResolved.template);
        print(UserText.teardownDescription.format({'resolvedDescription': _truncate(resolvedDescription)}));
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
      print(UserText.teardownReminderSavedRunClaudartArchivesTo.template);
    }
    print(UserText.teardownComeBackWhenTheFixIs.template);
    exit_(0);
  }

  // ── Run teardown analyzer (haiku) to pre-fill all metadata ─────────────────

  print('');
  final exec = executor ?? PipelineExecutor();
  SessionLogger.forEntry(entry, io: fileIO).logPipelineEvents(
    exec.events,
    command: ClaudartCommand.teardown.name,
  );
  final analyzerCtx = await exec.runFuture(
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
    print(UserText.teardownSessionRecordType.template);
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
    print(UserText.teardownCategorizeThisSessionForSkillsMd.template);
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
      : (HandoffPlaceholder.isBlank(changedFiles)
          ? null
          : changedFiles.replaceAll('\n', ', ').trim());
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
      : (HandoffPlaceholder.isBlank(rootCause)
          ? null
          : rootCause.replaceAll('\n', ' ').trim());
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
    print(UserText.teardownHeadlessDecisionsVerifyBeforeTrustingThe.template);
    print(render.divider());
    print(UserText.teardownRecordTypeLine.format({
      'recordType': (archiveKind == ArchiveKind.archive
              ? UserText.teardownRecordTypeArchive
              : UserText.teardownRecordTypeReminder)
          .template,
    }));
    print(UserText.teardownCategory.format({'category': category}));
    print(UserText.teardownFixSummary.format({'fixSummary': fixSummary}));
    print(UserText.teardownHotFilesLine.format({
      'hotFiles': hotFiles ?? UserText.teardownHotFilesUnspecified.template,
    }));
    print(UserText.teardownColdFilesLine.format({
      'coldFiles': coldFiles ?? UserText.teardownColdFilesNone.template,
    }));
    print(UserText.teardownRootCause.format({'pattern': pattern}));
    print(UserText.teardownFixPattern.format({'fixPattern': fixPattern}));
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
        handoff:     archivedHandoff,
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
    print(UserText.errorMessageLine.format({'toString': e.toString()}));
    exit_(1);
  }

  // Record the move once the guarded close succeeded. Not enforced: teardown
  // is deliberately permissive (a human may confirm "resolved" from any
  // status), so a status the table lacks is logged, not thrown.
  SessionLogger.forEntry(entry, io: fileIO).logHandoffMove(
    command: ClaudartCommand.teardown.name,
    from: readHandoffStatus(handoff),
    event: archiveKind == ArchiveKind.archive
        ? HandoffEvent.tornDown
        : HandoffEvent.reminderSaved,
  );

  // Suggest commit message.
  final commitMsg = buildCommitMessage(area, bug, rootCause, fixSummary!);

  if (archiveKind != ArchiveKind.reminder) {
    print(UserText.teardownSkillsUpdated.format({'workspace': skillsPathFor(workspace)}));
  }
  print(UserText.teardownHandoffArchived.format({'archiveFile': archiveFile}));
  print(UserText.teardownHandoffReset.template);
  print(render.divider());
  print(UserText.teardownSuggestedCommitMessage.template);
  print(commitMsg);
  print(render.divider());
  print(UserText.teardownRememberDoNotPushToRemote.template);
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
  apiIntegration(value: 'api-integration', area: 'api'),
  concurrency(value: 'concurrency', area: 'async'),
  configuration(value: 'configuration', area: 'config'),
  dataParsing(value: 'data-parsing', area: 'data'),
  ioFilesystem(value: 'io-filesystem', area: 'io'),
  stateManagement(value: 'state-management', area: 'state'),
  general(value: 'general', area: 'fix'),
  other(value: 'other', area: 'fix');

  const TeardownCategory({required this.value, required this.area});

  /// Canonical string written to skills.md.
  final String value;

  /// Commit area label for buildCommitMessage.
  final String area;

  /// Display label shown in the interactive menu.
  String get label => this == other ? 'other (type manually)' : value;
}

List<String> get _kCategories =>
    TeardownCategory.values.map((c) => c.label).toList();

String? _defaultPrompt(String question, {bool optional = false}) =>
    prompt(question, optional: optional);



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

