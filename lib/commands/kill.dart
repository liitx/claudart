import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../logging/logger.dart';
import '../session/md_io.dart' show confirmOrEof, readHandoffStatus;
import '../config/paths.dart';
import 'support/claudart_command.dart';
import '../session/handoff_event.dart';
import '../session/run_mode.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/workspace_guard.dart';
import '../workspace/workspace_link_state.dart';
import '../ui/render.dart' as render;
import 'support/command_seams.dart';
import 'support/project_resolution.dart';

/// How a `kill` run ended. The name is the outcome written to the interaction
/// log, so a warned kill, a cancelled one and a refused one can be told apart.
enum KillOutcome {
  /// Archived and reset; nothing the session learned was at stake.
  killed,

  /// Archived and reset from a status whose learning only `teardown` keeps; the
  /// owner was warned and confirmed.
  killedWithWarning,

  /// The owner declined a confirmation.
  cancelled,

  /// Nobody was there to answer, so nothing was changed.
  noInput,

  /// The workspace was locked by an interrupted operation and the lock stayed.
  lockNotCleared,

  /// Closing the session failed and was rolled back.
  closeFailed,

  /// Another operation held the workspace lock.
  workspaceLocked,
}

/// Abandons the active session for the current project.
///
/// Unlike `teardown`, kill does not update skills.md or suggest a commit.
/// It is for cases where the session needs to be discarded cleanly —
/// archive is still written so the work is not lost.
///
/// Consent: it asks. If there is nobody to answer (stdin closed) it stops
/// without changing anything, instead of reporting a "cancelled" that nobody
/// chose. A caller that means "kill, don't ask" (zedup's `/kill`, a script)
/// passes [RunMode.headless] (`claudart kill --headless`). Headless answers the
/// final confirmation and the two benign, reversible ones (no active session,
/// nothing to archive) with yes, since the handoff is archived either way, but
/// it never clears a workspace lock: that means another operation may be
/// running, and only a person can judge that.
Future<void> runKill({
  CommandSeams seams = const CommandSeams(),
  RunMode mode = RunMode.interactive,
}) async {
  final io = seams.io;
  final confirmFn = seams.confirmFn;
  final askFn = seams.askFn;
  final exitFn = seams.exitFn;
  final fileIO = io ?? const RealFileIO();
  final headless = mode == RunMode.headless;
  // A caller-supplied confirm always answers; the default reports null at end
  // of input. [askFn] lets a test simulate "nobody to answer".
  final bool? Function(String question) ask =
      askFn ?? (confirmFn != null ? (String q) => confirmFn(q) : confirmOrEof);
  final exit_ = exitFn ?? exit;
  final sw = Stopwatch()..start();
  // Null until the project is known: a run that cannot find a project has no
  // workspace to record in, and a command outside any project writes nothing.
  SessionLogger? logger;

  /// Records how the run ended, then exits with [code].
  Never leave(KillOutcome outcome, int code) {
    logger?.logInteraction(
      command: ClaudartCommand.kill.name,
      outcome: outcome.name,
    );
    exit_(code);
  }

  /// One decision point. Headless never prompts: it uses [headlessAnswer].
  bool decide(String question, {required bool headlessAnswer}) {
    if (headless) return headlessAnswer;
    final answer = ask(question);
    if (answer == null) {
      print('\n✗ No input available to answer "$question", so nothing was changed.');
      print('  Re-run in a terminal, or pass --headless to kill without asking.\n');
      leave(KillOutcome.noInput, 1);
    }
    return answer;
  }

  print(render.header('CLAUDART SESSION KILL'));

  // 1 — Detect project root and look it up in the registry.
  final project = requireProject(seams, withGitContext: true);
  final projectRoot = project.projectRoot;
  final registry = project.registry;
  final entry = project.entry;
  final gitCtx = project.gitContext;
  print('Project  : ${entry.name}');
  final recorder = SessionLogger.forEntry(entry, io: fileIO);
  logger = recorder;

  final workspace = entry.workspacePath;

  // 3 — Guard check — interrupted state.
  if (isLocked(workspace, io: fileIO)) {
    final op = interruptedOperation(workspace, io: fileIO) ?? 'unknown';
    print('\n⚠  Workspace is locked (interrupted during: $op).');
    print('   Another operation may still be running, or a previous run crashed.');
    if (!decide('Clear the lock and force kill?', headlessAnswer: false)) {
      print('\nKill cancelled. Resolve the interrupted state before retrying.');
      if (headless) print('  (--headless never clears a workspace lock; re-run in a terminal.)');
      print('');
      leave(KillOutcome.lockNotCleared, headless ? 1 : 0);
    }
    clearLock(workspace, io: fileIO);
  }

  // 4 — Check for an active session: a linked project (symlink or the real
  // directory fallback). Only warn when it is unlinked.
  if (!linkStateOf(fileIO, projectRoot).isLinked) {
    print('\n⚠  No active session found for ${entry.name}.');
    if (!decide('Kill anyway and archive the handoff?', headlessAnswer: true)) {
      print('\nKill cancelled.\n');
      leave(KillOutcome.cancelled, 0);
    }
  }

  // 5 — Read and display session state.
  final handoffPath = handoffPathFor(workspace);
  final handoff = fileIO.fileExists(handoffPath) ? fileIO.read(handoffPath) : '';
  if (handoff.isEmpty) {
    print('\n⚠  No handoff found in workspace: $workspace');
    if (!decide('Nothing to archive. Reset the session anyway?', headlessAnswer: true)) {
      print('\nKill cancelled.\n');
      leave(KillOutcome.cancelled, 0);
    }
  } else {
    final state = SessionState.parse(handoff);
    _printSessionSummary(entry.name, state, gitCtx?.branch);
  }

  // 6 — Final confirmation.
  if (headless) print('\n(headless — killing without confirmation)');
  if (!decide('Kill this session? (archive will be saved, skills.md will NOT be updated)',
      headlessAnswer: true)) {
    print('\nKill cancelled.\n');
    leave(KillOutcome.cancelled, 0);
  }

  // 7 — Execute transactional close under guard.
  try {
    await withGuard(workspace, 'kill', () async {
      await closeSession(workspace, projectRoot, io: fileIO);
    }, io: fileIO);
  } on SessionCloseException catch (e) {
    print('\n✗ Kill failed at step "${e.failedStep}": ${e.cause}');
    print('  Workspace state has been rolled back. No partial changes remain.\n');
    // closeSession's own rollback already restored the workspace, so the
    // lock withGuard left behind is not signaling a real interrupted state.
    clearLock(workspace, io: fileIO);
    leave(KillOutcome.closeFailed, 1);
  } on WorkspaceLockedException catch (e) {
    print('\n✗ ${e.toString()}\n');
    leave(KillOutcome.workspaceLocked, 1);
  }

  // Record the move only after the close succeeded. Not enforced: kill is
  // deliberately permissive, so a status the table lacks is logged, not thrown.
  recorder.logHandoffMove(
    command: ClaudartCommand.kill.name,
    from: readHandoffStatus(handoff),
    event: HandoffEvent.killed,
  );
  recorder.logInteraction(
    command: ClaudartCommand.kill.name,
    outcome: (SessionState.parse(handoff).effectiveStatus.killWarning == null
            ? KillOutcome.killed
            : KillOutcome.killedWithWarning)
        .name,
  );

  // 8 — Update registry timestamp.
  registry.touchSession(entry.name).save(io: fileIO);

  sw.stop();
  print('\n✓ Session killed: ${entry.name}  (${sw.elapsedMilliseconds}ms)');
  print('  Handoff archived to ${p.join(workspace, 'archive')}');
  print('  Handoff reset to blank.\n');
  print('Run `claudart setup` to start a new session.\n');
}

void _printSessionSummary(String name, SessionState state, String? liveBranch) {
  print('\n───────────────────────────────────────');
  print('  Session: $name');
  print('  Branch : ${liveBranch ?? state.branch}');
  print('  Status : ${state.effectiveStatus.value}');
  print('  Bug    : ${_truncate(state.bug.text)}');
  final warning = state.effectiveStatus.killWarning;
  if (warning != null) print('\n⚠  $warning');
  if (state.hasActiveContent) {
    print('\n  Debug progress recorded — this work will be archived.');
    if (!state.attempted.isBlank) {
      print('  Attempted : ${_truncate(state.attempted.text)}');
    }
    if (!state.changed.isBlank) {
      print('  Changed   : ${_truncate(state.changed.text)}');
    }
  } else {
    print('\n  No debug progress recorded (fresh session).');
  }
  print('───────────────────────────────────────');
}

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;


