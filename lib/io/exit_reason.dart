// exit_reason.dart — every reason a command leaves the process early
//
// A command that cannot go on, or has nothing left to do, leaves through
// [leaveFor] with one of these, never through a bare exit code. The reason
// carries the exit code and its name is recorded on the run's row in
// `interactions.jsonl`, so a diagram of the run says why it ended and a new
// way of leaving fails to compile until someone names it.
//
// Three commands keep their own typed endings, recorded as the run's outcome:
// `debug` ([DebugExitKind]), `kill` (`KillOutcome`) and the project lookup
// (`ProjectLookupFailure`).

import 'process_exit.dart';

enum ExitReason {
  // ── bin/claudart.dart: the command line itself ──────────────────────────────

  /// `--project` was given with no project name after it.
  projectOptionMissingName(exitCode: 1),

  /// `--project <name>` was given with no command after it.
  projectOptionMissingCommand(exitCode: 1),

  /// `--project` was given to a command that does not take it.
  projectOptionUnsupported(exitCode: 1),

  /// The project named by `--project` is not a linked project.
  projectOptionNotFound(exitCode: 1),

  /// `--help` or `-h` printed the usage and there was nothing else to do.
  usageShown(exitCode: 0),

  /// `--version` printed the version and there was nothing else to do.
  versionShown(exitCode: 0),

  /// The first word is not a command claudart knows.
  unknownCommand(exitCode: 1),

  /// The interactive launcher closed after the owner picked a command.
  launcherClosed(exitCode: 0),

  /// A command threw a typed failure that the dispatch printed.
  commandFailed(exitCode: 1),

  /// `rotate` stopped because the build gate failed, so scripts see exit 1.
  rotateBuildFailed(exitCode: 1),

  /// `compile` rebuilt the binary.
  compileSucceeded(exitCode: 0),

  /// `compile` could not rebuild the binary; the process leaves with the exit
  /// code of the build that failed, which [leaveFor] takes as `childCode`.
  compileFailed(exitCode: 1, passesChildCode: true),

  /// `hook` was run with no known subcommand.
  hookUsageShown(exitCode: 1),

  // ── terminal input ─────────────────────────────────────────────────────────

  /// The owner pressed Ctrl-C in an arrow-key menu.
  menuInterrupted(exitCode: 0),

  /// A numbered menu was asked for a choice but standard input was closed.
  menuHasNoInput(exitCode: 1),

  /// The owner pressed Ctrl-C in the line editor.
  lineEditorInterrupted(exitCode: 0),

  // ── init ───────────────────────────────────────────────────────────────────

  /// The owner declined to re-initialise an existing workspace.
  initDeclined(exitCode: 0),

  /// The workspace has not been initialised, so there is nothing to link.
  initWorkspaceMissing(exitCode: 1),

  /// The owner chose to keep a starter file that already exists.
  initKeptExistingFile(exitCode: 0),

  // ── add, archives, resume, launch, chat shell, confirm ─────────────────────

  /// `add` ran outside a git repository.
  addNotInGitRepository(exitCode: 1),

  /// The project has no archived sessions to list.
  archivesNone(exitCode: 0),

  /// The owner closed the archive list without choosing one.
  archivesCancelled(exitCode: 0),

  /// The project has no archived session to resume.
  resumeNoArchives(exitCode: 0),

  /// The launcher ran outside a linked project, so it has nothing to launch.
  launchOutsideProject(exitCode: 0),

  /// The chat shell ran outside a registered project.
  chatShellNotInRegisteredProject(exitCode: 0),

  /// `confirm-pending` was run without its question and its action.
  confirmPendingMissingArguments(exitCode: 1),

  // ── save, teardown ─────────────────────────────────────────────────────────

  /// `save` found no handoff, so it had nothing to checkpoint.
  saveNoHandoff(exitCode: 0),

  /// `teardown` found no handoff, so it had nothing to close.
  teardownNoHandoff(exitCode: 0),

  /// `teardown` stopped because the fix is not confirmed yet; the owner comes
  /// back when it is.
  teardownDeferredUntilFixed(exitCode: 0),

  /// `teardown` stopped because another command holds the workspace lock.
  teardownWorkspaceLocked(exitCode: 1),

  // ── suggest ────────────────────────────────────────────────────────────────

  /// `suggest` found no handoff to read.
  suggestNoHandoff(exitCode: 1),

  /// The owner declined to overwrite an existing root cause.
  suggestOverwriteDeclined(exitCode: 0),

  /// The handoff lists no files in play, so there is nothing to read.
  suggestNoScopeFiles(exitCode: 1),

  /// The reader step gave no output, usually because the `claude` CLI is not
  /// installed or not signed in.
  suggestReaderProducedNothing(exitCode: 1),

  /// The reasoner step gave no output.
  suggestReasonerProducedNothing(exitCode: 1),

  /// The owner reviewed the result and chose not to write the handoff.
  suggestHandoffNotWritten(exitCode: 0),

  // ── setup ──────────────────────────────────────────────────────────────────

  /// `setup` ran outside a git repository.
  setupNotInGitRepository(exitCode: 1),

  /// The project root `setup` was given does not exist.
  setupPathNotFound(exitCode: 1),

  /// The project is not linked, so `setup` has no workspace to write to.
  setupNotLinked(exitCode: 1),

  /// `setup` needs answers from a terminal and had none.
  setupNeedsTerminal(exitCode: 1),

  /// The owner declined to write the handoff.
  setupCancelled(exitCode: 0),

  // ── a live handoff the owner chose to keep ─────────────────────────────────

  /// The owner chose to continue the existing session.
  liveHandoffContinued(exitCode: 0),

  /// The owner went back and left the existing session as it was.
  liveHandoffLeftAlone(exitCode: 0),

  // ── link ───────────────────────────────────────────────────────────────────

  /// `link` was given an option it does not know.
  linkUnknownOption(exitCode: 1),

  /// `link` was given both the sensitive and the not-sensitive flag.
  linkConflictingSensitivityFlags(exitCode: 1),

  /// `link` ran outside a git repository.
  linkNotInGitRepository(exitCode: 1),

  /// `link` had to ask whether the project is sensitive and had no one to ask.
  linkNoInputForSensitivity(exitCode: 1),

  // ── flow ───────────────────────────────────────────────────────────────────

  /// The owner chose to keep the checkpoint and stop.
  flowCheckpointKept(exitCode: 0),

  /// The owner entered no prompt.
  flowNoPrompt(exitCode: 0),

  /// The flow stopped after saving a checkpoint.
  flowCheckpointSaved(exitCode: 0),

  /// The owner did not approve the plan, so no handoff was written.
  flowNotApproved(exitCode: 0),

  /// The construct step produced no handoff.
  flowProducedNoHandoff(exitCode: 1),

  // ── rotate, preflight, doctor, experiment ──────────────────────────────────

  /// `rotate` had to confirm and had no one to ask.
  rotateNoInputToConfirm(exitCode: 1),

  /// `preflight` was asked for an operation it does not know.
  preflightUnknownOperation(exitCode: 1),

  /// `preflight` found nothing wrong.
  preflightClean(exitCode: 0),

  /// `preflight` found warnings only; they allow continuing.
  preflightWarnings(exitCode: 0),

  /// `preflight` found errors; they block continuing.
  preflightErrors(exitCode: 1),

  /// `doctor` ran every check and none failed.
  doctorChecksPassed(exitCode: 0),

  /// `doctor` ran every check and at least one failed.
  doctorChecksFailed(exitCode: 1),

  /// `experiment` was given no name, no separator or no command.
  experimentUsageShown(exitCode: 1),

  /// The command `experiment` ran failed; the process leaves with that
  /// command's own exit code, which [leaveFor] takes as `childCode`.
  experimentCommandFailed(exitCode: 1, passesChildCode: true);

  const ExitReason({required this.exitCode, this.passesChildCode = false});

  /// The process exit code for this ending.
  final int exitCode;

  /// Whether the process leaves with the exit code of a command this one ran,
  /// instead of [exitCode].
  final bool passesChildCode;
}

/// Records [reason] on the run in progress, then leaves through [exit_] (the
/// command's own seam, defaulting to [exitProcess]) with the reason's code.
Never leaveFor(
  ExitReason reason, {
  Never Function(int code)? exit_,
  int? childCode,
}) {
  assert(
    childCode == null || reason.passesChildCode,
    '${reason.name} does not leave with another command\'s exit code',
  );
  noteExitReason(reason);
  (exit_ ?? exitProcess)(childCode ?? reason.exitCode);
}
