import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../file_io.dart';
import '../git_utils.dart';
import '../handoff_template.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../teardown_utils.dart';
import '../md_io.dart' show confirm;

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
/// Gate: runs [buildFn] (defaults to the workspace `afterFixCommand`) between
/// archiving and seeding. If the build fails the rotation is aborted — the
/// archive already written remains, but the live handoff is not overwritten.
Future<RotateResult>  runRotate({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  bool Function(String question)? confirmFn,
  Future<bool> Function(String command)? buildFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final confirm_ = confirmFn ?? confirm;
  final build_ = buildFn ?? _defaultBuild;

  print('\n═══════════════════════════════════════');
  print('  CLAUDART ROTATE');
  print('═══════════════════════════════════════');

  // 1 — Registry lookup.
  final projectRoot = projectRootOverride ?? await (await detectGitContext())?.root;
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

  if (!fileIO.fileExists(handoffFile)) {
    print('\n⚠  No handoff found in workspace. Nothing to rotate.\n');
    return RotateResult.noHandoff;
  }

  final handoff = fileIO.read(handoffFile);
  final state = SessionState.parse(handoff);

  if (!state.hasActiveContent) {
    print('\n⚠  Handoff is blank. Start a session with /suggest first.\n');
    return RotateResult.noHandoff;
  }

  // 2 — Show current session summary.
  print('\n───────────────────────────────────────');
  print('  Bug    : ${_truncate(state.bug)}');
  print('  Branch : ${state.branch}');
  print('───────────────────────────────────────\n');

  // 3 — Confirm before any destructive action.
  if (!confirm_('Archive this session and rotate to the next issue?')) {
    print('\nRotate cancelled.\n');
    return RotateResult.cancelled;
  }

  // 4 — Extract pending issues before overwriting anything.
  final pending = extractPendingIssues(handoff);

  // 5 — Archive current handoff.
  final archiveDirectory = archiveDirFor(workspace);
  fileIO.createDir(archiveDirectory);
  final archiveFile = p.join(archiveDirectory, archiveName(state.branch));
  fileIO.write(archiveFile, handoff);

  // 6 — Build gate: must pass before the next session can start.
  final config = _loadConfig(fileIO, workspace);
  print('\nRunning build gate: ${config.afterFixCommand}');
  final buildOk = await build_(config.afterFixCommand);
  if (!buildOk) {
    print('✗ Build failed. Fix the build before rotating.\n');
    return RotateResult.buildFailed;
  }
  print('✓ Build passed.\n');

  // 7 — Seed next handoff or reset to blank.
  if (pending.isEmpty) {
    fileIO.write(handoffFile, blankHandoff);
    print('✓ Archived  : ${p.basename(archiveFile)}');
    print('✓ All pending issues cleared. Handoff reset.\n');
    return RotateResult.noNextIssue;
  }

  final nextBug = pending.first;
  final remaining = pending.skip(1).toList();
  final date = DateTime.now().toIso8601String().split('T').first;

  final newHandoff = handoffTemplate(
    branch: state.branch,
    date: date,
    bug: nextBug,
    expected: '_Not yet determined._',
    projectName: entry.name,
    pendingIssues: remaining,
  );
  fileIO.write(handoffFile, newHandoff);

  print('✓ Archived  : ${p.basename(archiveFile)}');
  print('✓ Next issue: ${_truncate(nextBug)}');
  if (remaining.isNotEmpty) {
    print('  Queued    : ${remaining.length} more issue(s) in Pending Issues.');
  }
  print('\nRun /suggest to continue.\n');

  return RotateResult.rotated;
}

WorkspaceConfig _loadConfig(FileIO fileIO, String workspace) {
  final configFile = configPathFor(workspace);
  if (!fileIO.fileExists(configFile)) return const WorkspaceConfig();
  try {
    final json = jsonDecode(fileIO.read(configFile)) as Map<String, dynamic>;
    return WorkspaceConfig.fromJson(json);
  } on FormatException {
    return const WorkspaceConfig();
  }
}

Future<bool> _defaultBuild(String command) async {
  final parts = command.split(' ');
  final result = await Process.run(
    parts.first,
    parts.skip(1).toList(),
    runInShell: true,
  );
  return result.exitCode == 0;
}

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
