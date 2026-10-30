
import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../logging/logger.dart';
import '../config/paths.dart';
import '../sensitivity/abstractor.dart';
import '../templates/handoff_template.dart' show stampHandoffUpdated;
import '../session/handoff_event.dart';
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../ui/render.dart' as render;
import 'support/claudart_command.dart';
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../session/handoff_store.dart';

/// Result of the skills.md pending update — used in reports and tests.
enum SkillsUpdateResult { written, skipped }

/// Checkpoints the current session state without ending it.
///
/// Writes a dated snapshot to archive/ and appends confirmed facts to the
/// skills.md pending section. Does NOT reset the handoff or remove the symlink
/// — those are teardown/kill's responsibility.
Future<SkillsUpdateResult> runSave({
  CommandSeams seams = const CommandSeams(),
}) async {
  final io = seams.io;
  final exitFn = seams.exitFn;
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final sw = Stopwatch()..start();
  final now = (seams.clock ?? DateTime.now)();

  print(render.header('CLAUDART SAVE'));

  // 1 — Registry lookup.
  final project = requireProject(seams, withGitContext: true);
  final entry = project.entry;
  final registry = project.registry;
  final gitCtx = project.gitContext;
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);

  // 2 — Read handoff.
  if (!fileIO.fileExists(handoffFile)) {
    print(UserText.saveNoHandoffFoundInWorkspaceNothing.template);
    exit_(0);
  }

  var handoff = fileIO.read(handoffFile);
  final state = SessionState.parse(handoff);

  // 2b — Apply the save event: root cause confirmed or not. A save from a
  // status with no such move (or no session) is a plain checkpoint.
  final saveEvent = state.rootCause.isBlank
      ? HandoffEvent.saveUnconfirmed
      : HandoffEvent.saveConfirmedExploring;
  final logger = SessionLogger.forEntry(entry, io: fileIO);
  final store = HandoffStore(
    io: fileIO,
    handoffFile: handoffFile,
    logger: logger,
    command: ClaudartCommand.save.name,
  );
  if (state.effectiveStatus.after(saveEvent) != null) {
    handoff = store.apply(handoff, saveEvent);
  }

  // 3 — Stamp updated timestamp and persist.
  handoff = stampHandoffUpdated(handoff, now: now);
  store.rewrite(handoff);

  // 3b — Write checkpoint to archive/.
  final archiveDir = archiveDirFor(workspace);
  fileIO.createDir(archiveDir);
  final checkpointFile = p.join(archiveDir, _checkpointName(state.branch, now));
  fileIO.write(checkpointFile, handoff);

  // 4 — Append confirmed facts to skills.md pending section.
  final skillsFile = skillsPathFor(workspace);
  final skillsResult = _updatePendingSkills(
    fileIO: fileIO,
    skillsFile: skillsFile,
    tokenMapFile: tokenMapPathFor(workspace),
    sensitivityMode: entry.sensitivityMode,
    state: state,
  );

  // 5 — Touch registry.
  registry.touchSession(entry.name).save(io: fileIO);

  // 6 — Report.
  sw.stop();
  _printReport(entry.name, SessionState.parse(handoff), gitCtx?.branch, checkpointFile, skillsResult, sw.elapsedMilliseconds);

  return skillsResult;
}

// ── Skills update ─────────────────────────────────────────────────────────────

SkillsUpdateResult _updatePendingSkills({
  required FileIO fileIO,
  required String skillsFile,
  required String tokenMapFile,
  required bool sensitivityMode,
  required SessionState state,
}) {
  if (state.rootCause.isBlank) {
    return SkillsUpdateResult.skipped;
  }

  var skills = fileIO.fileExists(skillsFile)
      ? fileIO.read(skillsFile)
      : _blankSkillsTemplate;

  // Abstract KT content before writing when sensitivity mode is on.
  // This ensures root cause and hot file paths are not written in plaintext.
  // One token map serves both texts, so two names never share a token.
  List<String> sanitize(List<String> texts) => sensitivityMode
      ? abstractTexts(texts, tokenMapPath: tokenMapFile, io: fileIO)
      : texts;

  // One upserted entry per branch — combines root cause and (optional) hot
  // files into a single keyed line, replacing any prior entry for this
  // branch instead of accumulating duplicate bullets on repeated /save.
  final changedText = state.changed.isBlank
      ? null
      : state.changed.text.replaceAll('\n', ' ').trim();
  final safe = sanitize([
    state.rootCause.text.replaceAll('\n', ' ').trim(),
    if (changedText != null) changedText,
  ]);
  final cause = safe.first;
  final changed = changedText == null ? null : safe.last;
  skills = upsertPendingEntry(skills, state.branch, rootCause: cause, hotFiles: changed);

  fileIO.write(skillsFile, skills);
  return SkillsUpdateResult.written;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _checkpointName(String branch, DateTime now) {
  final ts = now
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final safeBranch = branch.replaceAll('/', '_').replaceAll(' ', '_');
  return 'checkpoint_${safeBranch}_$ts.md';
}


void _printReport(
  String projectName,
  SessionState state,
  String? liveBranch,
  String checkpointFile,
  SkillsUpdateResult skillsResult,
  int durationMs,
) {
  print(UserText.saveCheckpointMs.format({'checkpointFile': p.basename(checkpointFile), 'durationMs': durationMs}));
  print(UserText.killBranch.format({'branch': liveBranch ?? state.branch}));
  // A blank handoff is no-handoff, not its stale Status line.
  final shown = state.effectiveStatus;
  print(UserText.killStatus.format({'value': shown.value}));

  if (skillsResult == SkillsUpdateResult.written) {
    print(UserText.saveSkillsPendingEntryWrittenRootCause.template);
  } else {
    print(UserText.saveSkillsSkippedRootCauseNotYet.template);
  }

  print('');
  switch (shown) {
    case HandoffStatus.suggestInvestigating:
      print(UserText.saveContinueExploringRunSaveAgainWhen.template);
    case HandoffStatus.readyForSuggest:
      print(UserText.saveRunSuggestToContinue.template);
    case HandoffStatus.readyForDebug:
      print(UserText.saveRootCauseLockedRunDebugTo.template);
    case HandoffStatus.debugInProgress:
      print(UserText.saveFixInProgressRunSaveAgain.template);
    case HandoffStatus.debugComplete:
      print(UserText.saveDebugCompleteVerifyWithDartTest.template);
    case HandoffStatus.needsSuggest ||
         HandoffStatus.unknown ||
         HandoffStatus.noHandoff:
      print(UserText.saveRunSuggestOrDebugToContinue.template);
  }
  print('');
}

const String _blankSkillsTemplate = '''# Accumulated Skills
> Updated by claudart teardown and save. Do not edit manually.

---

## Pending

> Confirmed facts from in-progress sessions. Promoted to patterns by teardown.

_Nothing yet._

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
