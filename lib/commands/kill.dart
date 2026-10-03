import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../md_io.dart' show confirmOrEof;
import '../paths.dart';
import '../registry.dart';
import '../session/run_mode.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/workspace_guard.dart';
import '../ui/render.dart' as render;

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
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  bool? Function(String question)? askFn,
  RunMode mode = RunMode.interactive,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final headless = mode == RunMode.headless;
  // A caller-supplied confirm always answers; the default reports null at end
  // of input. [askFn] lets a test simulate "nobody to answer".
  final bool? Function(String question) ask =
      askFn ?? (confirmFn != null ? (String q) => confirmFn(q) : confirmOrEof);
  final exit_ = exitFn ?? exit;
  final sw = Stopwatch()..start();

  /// One decision point. Headless never prompts: it uses [headlessAnswer].
  bool decide(String question, {required bool headlessAnswer}) {
    if (headless) return headlessAnswer;
    final answer = ask(question);
    if (answer == null) {
      print('\n✗ No input available to answer "$question", so nothing was changed.');
      print('  Re-run in a terminal, or pass --headless to kill without asking.\n');
      exit_(1);
    }
    return answer;
  }

  print(render.header('CLAUDART SESSION KILL'));

  // 1 — Detect project root.
  final gitCtx = projectRootOverride != null ? null : detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;
  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project.\n');
    exit_(1);
  }

  // 2 — Registry lookup.
  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('\n✗ No claudart session found for this project.');
    print('  Run `claudart setup` to start one.\n');
    exit_(1);
  }
  print('Project  : ${entry.name}');

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
      exit_(headless ? 1 : 0);
    }
    clearLock(workspace, io: fileIO);
  }

  // 4 — Check for an active session. `.claude` is either a symlink (the
  // normal case) or a real directory when link.dart couldn't symlink it —
  // both mean a session is linked. Only warn when neither exists.
  final claudePath = p.join(projectRoot, '.claude');
  if (!fileIO.linkExists(claudePath) && !fileIO.dirExists(claudePath)) {
    print('\n⚠  No active session found for ${entry.name}.');
    if (!decide('Kill anyway and archive the handoff?', headlessAnswer: true)) {
      print('\nKill cancelled.\n');
      exit_(0);
    }
  }

  // 5 — Read and display session state.
  final handoffPath = handoffPathFor(workspace);
  final handoff = fileIO.fileExists(handoffPath) ? fileIO.read(handoffPath) : '';
  if (handoff.isEmpty) {
    print('\n⚠  No handoff found in workspace: $workspace');
    if (!decide('Nothing to archive. Remove symlink only?', headlessAnswer: true)) {
      print('\nKill cancelled.\n');
      exit_(0);
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
    exit_(0);
  }

  // 7 — Execute transactional close under guard.
  try {
    await withGuard(workspace, 'kill', () async {
      await closeSession(workspace, projectRoot, io: fileIO);
    }, io: fileIO);
  } on SessionCloseException catch (e) {
    print('\n✗ Kill failed at step "${e.failedStep}": ${e.cause}');
    print('  Workspace state has been rolled back. No partial changes remain.\n');
    exit_(1);
  } on WorkspaceLockedException catch (e) {
    print('\n✗ ${e.toString()}\n');
    exit_(1);
  }

  // 8 — Update registry timestamp.
  registry.touchSession(entry.name).save(io: fileIO);

  sw.stop();
  print('\n✓ Session killed: ${entry.name}  (${sw.elapsedMilliseconds}ms)');
  print('  Handoff archived to ${p.join(workspace, 'archive')}');
  print('  Handoff reset to blank.');
  print('  Symlink removed.\n');
  print('Run `claudart setup` to start a new session.\n');
}

void _printSessionSummary(String name, SessionState state, String? liveBranch) {
  print('\n───────────────────────────────────────');
  print('  Session: $name');
  print('  Branch : ${liveBranch ?? state.branch}');
  print('  Status : ${state.status.value}');
  print('  Bug    : ${_truncate(state.bug)}');
  if (state.hasActiveContent) {
    print('\n  Debug progress recorded — this work will be archived.');
    if (!_isBlank(state.attempted)) {
      print('  Attempted : ${_truncate(state.attempted)}');
    }
    if (!_isBlank(state.changed)) {
      print('  Changed   : ${_truncate(state.changed)}');
    }
  } else {
    print('\n  No debug progress recorded (fresh session).');
  }
  print('───────────────────────────────────────');
}

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

bool _isBlank(String s) =>
    s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');

