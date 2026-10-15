import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';
import '../sensitivity/token_map.dart';
import '../templates/handoff_template.dart' show stampHandoffUpdated;
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../ui/render.dart' as render;

/// Result of the skills.md pending update — used in reports and tests.
enum SkillsUpdateResult { written, skipped }

/// Checkpoints the current session state without ending it.
///
/// Writes a dated snapshot to archive/ and appends confirmed facts to the
/// skills.md pending section. Does NOT reset the handoff or remove the symlink
/// — those are teardown/kill's responsibility.
Future<SkillsUpdateResult> runSave({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final sw = Stopwatch()..start();

  print(render.header('CLAUDART SAVE'));

  // 1 — Registry lookup.
  final gitCtx = detectGitContext(workingDirectory: projectRootOverride);
  final projectRoot = projectRootOverride ?? gitCtx?.root;
  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project.\n');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('\n✗ No claudart session found for this project.');
    print('  Run `claudart setup` to start one.\n');
    exit_(1);
  }
  print('Project  : ${entry.name}');

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);

  // 2 — Read handoff.
  if (!fileIO.fileExists(handoffFile)) {
    print('\n⚠  No handoff found in workspace. Nothing to checkpoint.\n');
    exit_(0);
  }

  var handoff = fileIO.read(handoffFile);
  final state = SessionState.parse(handoff);

  // 3 — Stamp updated timestamp and persist.
  handoff = stampHandoffUpdated(handoff);
  fileIO.write(handoffFile, handoff);

  // 3b — Write checkpoint to archive/.
  final archiveDir = archiveDirFor(workspace);
  fileIO.createDir(archiveDir);
  final checkpointFile = p.join(archiveDir, _checkpointName(state.branch));
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
  _printReport(entry.name, state, gitCtx?.branch, checkpointFile, skillsResult, sw.elapsedMilliseconds);

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
  if (_isBlank(state.rootCause)) return SkillsUpdateResult.skipped;

  var skills = fileIO.fileExists(skillsFile)
      ? fileIO.read(skillsFile)
      : _blankSkillsTemplate;

  // Abstract KT content before writing when sensitivity mode is on.
  // This ensures root cause and hot file paths are not written in plaintext.
  String sanitize(String text) {
    if (!sensitivityMode) return text;
    final tokenMap = TokenMap.load(tokenMapFile);
    return abstractor.abstract(text, tokenMap, defaultDetector);
  }

  // One upserted entry per branch — combines root cause and (optional) hot
  // files into a single keyed line, replacing any prior entry for this
  // branch instead of accumulating duplicate bullets on repeated /save.
  final cause = sanitize(state.rootCause.replaceAll('\n', ' ').trim());
  final changed =
      _isBlank(state.changed) ? null : sanitize(state.changed.replaceAll('\n', ' ').trim());
  skills = upsertPendingEntry(skills, state.branch, rootCause: cause, hotFiles: changed);

  fileIO.write(skillsFile, skills);
  return SkillsUpdateResult.written;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _checkpointName(String branch) {
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final safeBranch = branch.replaceAll('/', '_').replaceAll(' ', '_');
  return 'checkpoint_${safeBranch}_$ts.md';
}

bool _isBlank(String s) =>
    s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');

void _printReport(
  String projectName,
  SessionState state,
  String? liveBranch,
  String checkpointFile,
  SkillsUpdateResult skillsResult,
  int durationMs,
) {
  print('\n✓ Checkpoint: ${p.basename(checkpointFile)}  (${durationMs}ms)');
  print('  Branch : ${liveBranch ?? state.branch}');
  // A blank handoff is no-handoff, not its stale Status line.
  final shown = state.effectiveStatus;
  print('  Status : ${shown.value}');

  if (skillsResult == SkillsUpdateResult.written) {
    print('  Skills : pending entry written (root cause confirmed)');
  } else {
    print('  Skills : skipped (root cause not yet confirmed)');
  }

  print('');
  switch (shown) {
    case HandoffStatus.suggestInvestigating:
      print('Continue exploring. Run /save again when root cause is confirmed.');
    case HandoffStatus.readyForSuggest:
      print('Run /suggest to continue.');
    case HandoffStatus.readyForDebug:
      print('Root cause locked. Run /debug to implement the fix.');
    case HandoffStatus.debugInProgress:
      print('Fix in progress. Run /save again after confirming the fix.');
    case HandoffStatus.debugComplete:
      print('Debug complete. Verify with dart test, then claudart teardown.');
    case HandoffStatus.needsSuggest ||
         HandoffStatus.unknown ||
         HandoffStatus.noHandoff:
      print('Run /suggest or /debug to continue.');
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
