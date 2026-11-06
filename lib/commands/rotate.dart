import 'dart:convert';
import '../session/handoff_placeholder.dart';
import 'package:path/path.dart' as p;
import '../config/config.dart';
import '../io/file_io.dart';
import '../logging/logger.dart';
import 'support/claudart_command.dart';
import '../templates/handoff_template.dart';
import '../config/paths.dart';
import '../session/archive_entry.dart';
import '../session/handoff_event.dart';
import '../session/run_mode.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../session/md_io.dart' show confirmOrEof;
import '../io/process_runner.dart';
import '../ui/render.dart' as render;
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../session/handoff_store.dart';
import '../io/process_exit.dart';
import '../io/gate_runner.dart';


enum RotateResult {
  /// Current session archived, next issue seeded into fresh handoff.
  rotated,

  /// Current session archived, no pending issues — handoff reset to blank.
  noNextIssue,

  /// Build gate failed — rotation aborted, handoff untouched.
  buildFailed,

  /// No active handoff found — nothing to rotate.
  noHandoff,

  /// User declined the confirm prompt.
  cancelled,
}

/// Archives the current session and seeds the next handoff from the first
/// unchecked item in `## Pending Issues`.
///
/// Consent: rotating archives the live handoff and runs the configured build
/// gate (`afterFixCommand`, an arbitrary shell command), so it never proceeds
/// on the mere absence of a terminal. It asks; if there is nobody to answer
/// (stdin closed) it stops without changing anything. A caller that really
/// means "don't ask" passes [RunMode.headless] (`claudart rotate --headless`).
///
/// Gate: runs [buildFn] (defaults to the workspace `afterFixCommand`) between
/// archiving and seeding. If the build fails the rotation is aborted — the
/// archive already written remains, but the live handoff is not overwritten.
Future<RotateResult>  runRotate({
  CommandSeams seams = const CommandSeams(),
  ProcessRunner? runner,
  Future<GateResult> Function(String command)? buildFn,
  RunMode mode = RunMode.interactive,
}) async {
  final io = seams.io;
  final exitFn = seams.exitFn;
  final confirmFn = seams.confirmFn;
  final askFn = seams.askFn;
  final fileIO = io ?? const RealFileIO();
  final proc = runner ?? const RealProcessRunner();
  final exit_ = exitFn ?? exitProcess;
  // A caller-supplied confirm always answers; the default reports null at end
  // of input. [askFn] lets a test simulate "nobody to answer".
  final bool? Function(String question) ask =
      askFn ?? (confirmFn != null ? (String q) => confirmFn(q) : confirmOrEof);

  print(render.header('CLAUDART ROTATE'));

  // 1 — Registry lookup.
  final project = requireProject(seams, withGitContext: true);
  final projectRoot = project.projectRoot;
  final entry = project.entry;
  final gitCtx = project.gitContext;
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);

  if (!fileIO.fileExists(handoffFile)) {
    print(UserText.rotateNoHandoffFoundInWorkspaceNothing.template);
    return RotateResult.noHandoff;
  }

  final handoff = fileIO.read(handoffFile);
  final state = SessionState.parse(handoff);

  if (!state.hasActiveContent) {
    print(UserText.rotateHandoffIsBlankStartASession.template);
    return RotateResult.noHandoff;
  }

  // 2 — Show current session summary.
  print(UserText.ruleLeadingBlank.template);
  print(UserText.killBug.format({'text': _truncate(state.bug.text)}));
  print(UserText.killBranch.format({'branch': gitCtx?.branch ?? state.branch}));
  print(UserText.ruleTrailingBlank.template);

  // 3 — Confirm before any destructive action.
  //
  // Consent is never inferred from the absence of a terminal: a caller with
  // no stdin (for example a chat pane shelling out via Process.runSync) used
  // to be waved through with "proceeding without confirmation", which ran
  // the build gate, an arbitrary configured command, unasked. Now
  // `--headless` is the explicit way to say "don't ask", and plain end of
  // input stops here. A piped answer still counts as an answer.
  if (mode == RunMode.headless) {
    print(UserText.rotateHeadlessProceedingWithoutConfirmation.template);
  } else {
    final answer = ask('Archive this session and rotate to the next issue?');
    if (answer == null) {
      print(UserText.rotateNoInputAvailableToConfirmThe.template);
      print(UserText.rotateReRunInATerminalOr.template);
      exit_(1);
    }
    if (!answer) {
      print(UserText.rotateRotateCancelled.template);
      return RotateResult.cancelled;
    }
  }

  // 4 — Extract pending issues before overwriting anything.
  final pending = extractPendingIssues(handoff);

  // 5 — Archive current handoff + index entry, so a rotated session is
  // visible to `claudart archives` like a killed or torn-down one is.
  final archiveEntry = writeArchiveEntry(
    workspace:   workspace,
    branch:      state.branch,
    handoff:     handoff,
    kind:        ArchiveKind.reminder,
    description: state.bug.text,
    io:          fileIO,
  );
  final archiveFile = p.join(archiveDirFor(workspace), archiveEntry.handoffFile);

  final logger = SessionLogger.forEntry(entry, io: fileIO);

  // 6 — Build gate: must pass before the next session can start.
  // afterFixCommand has no registry-entry field yet, so it stays sourced
  // from the workspace config.json, defaulting to 'make rebuild'.
  final config = _loadConfig(fileIO, workspace);
  final build_ = buildFn ??
      (command) => runGate(proc, command, projectRoot, clock: seams.clock);
  print(UserText.rotateRunningBuildGate.format({'afterFixCommand': config.afterFixCommand}));
  final gate = await build_(config.afterFixCommand);
  logger.logGate(
    command: ClaudartCommand.rotate.name,
    gate: GateKind.rotateBuild,
    shellCommand: config.afterFixCommand,
    result: gate,
  );
  if (!gate.passed) {
    print(UserText.rotateBuildFailedFixTheBuildBefore.template);
    print(UserText.rotateGateChangeItWithAfterfixcommandIn.format({'afterFixCommand': config.afterFixCommand, 'workspace': configPathFor(workspace)}));
    return RotateResult.buildFailed;
  }
  print(UserText.rotateBuildPassed.template);

  // Records the move once the build gate has passed and the handoff is about
  // to change. Not enforced: rotate is deliberately permissive, so a status
  // the table lacks is logged, not thrown.
  final store = HandoffStore(
    io: fileIO,
    handoffFile: handoffFile,
    logger: logger,
    command: ClaudartCommand.rotate.name,
  );

  // 7 — Seed next handoff or reset to blank.
  if (pending.isEmpty) {
    store.replace(
      blankHandoff,
      from: state.status,
      event: HandoffEvent.rotatedEmpty,
    );
    print(UserText.rotateArchived.format({'archiveFile': p.basename(archiveFile)}));
    print(UserText.rotateAllPendingIssuesClearedHandoffReset.template);
    return RotateResult.noNextIssue;
  }

  final nextBug = pending.first;
  final remaining = pending.skip(1).toList();
  final date = DateTime.now().toIso8601String().split('T').first;

  final newHandoff = handoffTemplate(
    branch: state.branch,
    date: date,
    bug: nextBug,
    expected: notYetDeterminedText,
    projectName: entry.name,
    pendingIssues: remaining,
  );
  store.replace(
    newHandoff,
    from: state.status,
    event: HandoffEvent.rotated,
  );

  print(UserText.rotateArchived.format({'archiveFile': p.basename(archiveFile)}));
  print(UserText.rotateNextIssue.format({'nextBug': _truncate(nextBug)}));
  if (remaining.isNotEmpty) {
    print(UserText.rotateQueuedMoreIssueSInPending.format({'length': remaining.length}));
  }
  print(UserText.rotateRunSuggestToContinue.template);

  return RotateResult.rotated;
}

ProjectConfig _loadConfig(FileIO fileIO, String workspace) {
  final configFile = configPathFor(workspace);
  if (!fileIO.fileExists(configFile)) return const ProjectConfig();
  try {
    final json = jsonDecode(fileIO.read(configFile)) as Map<String, dynamic>;
    return ProjectConfig.fromJson(json);
  } on FormatException {
    return const ProjectConfig();
  }
}

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
