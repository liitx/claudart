import 'dart:io';
import '../ui/line_editor.dart' as editor;
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_ops.dart';
import '../session/session_state.dart';
import '../session/workspace_guard.dart';

/// Abandons the active session for the current project.
///
/// Unlike `teardown`, kill does not update skills.md or suggest a commit.
/// It is for cases where the session needs to be discarded cleanly —
/// archive is still written so the work is not lost.
Future<void> runKill({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final confirm_ = confirmFn ?? _defaultConfirm;
  final exit_ = exitFn ?? exit;
  final sw = Stopwatch()..start();

  print('\n═══════════════════════════════════════');
  print('  CLAUDART SESSION KILL');
  print('═══════════════════════════════════════');

  // 1 — Detect project root.
  final projectRoot = projectRootOverride ?? (await detectGitContext())!.root;
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

  final workspace = entry.workspacePath;

  // 3 — Guard check — interrupted state.
  if (isLocked(workspace, io: fileIO)) {
    final op = interruptedOperation(workspace, io: fileIO) ?? 'unknown';
    print('\n⚠  Workspace is locked (interrupted during: $op).');
    print('   Another operation may still be running, or a previous run crashed.');
    if (!confirm_('Clear the lock and force kill?')) {
      print('\nKill cancelled. Resolve the interrupted state before retrying.\n');
      exit_(0);
    }
    clearLock(workspace, io: fileIO);
  }

  // 4 — Check for an active session (symlink present).
  final symlinkPath = p.join(projectRoot, '.claude');
  if (!fileIO.linkExists(symlinkPath)) {
    print('\n⚠  No active session symlink found for ${entry.name}.');
    if (!confirm_('Kill anyway and archive the handoff?')) {
      print('\nKill cancelled.\n');
      exit_(0);
    }
  }

  // 5 — Read and display session state.
  final handoffPath = handoffPathFor(workspace);
  final handoff = fileIO.fileExists(handoffPath) ? fileIO.read(handoffPath) : '';
  if (handoff.isEmpty) {
    print('\n⚠  No handoff found in workspace: $workspace');
    if (!confirm_('Nothing to archive. Remove symlink only?')) {
      print('\nKill cancelled.\n');
      exit_(0);
    }
  } else {
    final state = SessionState.parse(handoff);
    _printSessionSummary(entry.name, state);
  }

  // 6 — Final confirmation.
  if (!confirm_('Kill this session? (archive will be saved, skills.md will NOT be updated)')) {
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

void _printSessionSummary(String name, SessionState state) {
  print('\n───────────────────────────────────────');
  print('  Session: $name');
  print('  Branch : ${state.branch}');
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

bool _defaultConfirm(String question) {
  stdout.write('\n$question [y/n]\n');
  final input = editor.readLine(optional: true);
  return input?.toLowerCase() == 'y' || input?.toLowerCase() == 'yes';
}

