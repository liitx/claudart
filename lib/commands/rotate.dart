import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../file_io.dart';
import '../git_utils.dart';
import '../templates/handoff_template.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/run_mode.dart';
import '../session/session_state.dart';
import '../session/teardown_utils.dart';
import '../md_io.dart' show confirmOrEof;
import '../process_runner.dart';
import '../ui/render.dart' as render;

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
  FileIO? io,
  ProcessRunner? runner,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  bool Function(String question)? confirmFn,
  bool? Function(String question)? askFn,
  Future<bool> Function(String command)? buildFn,
  RunMode mode = RunMode.interactive,
}) async {
  final fileIO = io ?? const RealFileIO();
  final proc = runner ?? const RealProcessRunner();
  final exit_ = exitFn ?? exit;
  // A caller-supplied confirm always answers; the default reports null at end
  // of input. [askFn] lets a test simulate "nobody to answer".
  final bool? Function(String question) ask =
      askFn ?? (confirmFn != null ? (String q) => confirmFn(q) : confirmOrEof);

  print(render.header('CLAUDART ROTATE'));

  // 1 — Registry lookup.
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
  print('  Branch : ${gitCtx?.branch ?? state.branch}');
  print('───────────────────────────────────────\n');

  // 3 — Confirm before any destructive action.
  //
  // Consent is never inferred from the absence of a terminal: a caller with
  // no stdin (for example a chat pane shelling out via Process.runSync) used
  // to be waved through with "proceeding without confirmation", which ran
  // the build gate, an arbitrary configured command, unasked. Now
  // `--headless` is the explicit way to say "don't ask", and plain end of
  // input stops here. A piped answer still counts as an answer.
  if (mode == RunMode.headless) {
    print('(headless — proceeding without confirmation)\n');
  } else {
    final answer = ask('Archive this session and rotate to the next issue?');
    if (answer == null) {
      print('\n✗ No input available to confirm the rotation, so nothing was changed.');
      print('  Re-run in a terminal, or pass --headless to proceed without asking.\n');
      exit_(1);
    }
    if (!answer) {
      print('\nRotate cancelled.\n');
      return RotateResult.cancelled;
    }
  }

  // 4 — Extract pending issues before overwriting anything.
  final pending = extractPendingIssues(handoff);

  // 5 — Archive current handoff.
  final archiveDirectory = archiveDirFor(workspace);
  fileIO.createDir(archiveDirectory);
  final archiveFile = p.join(archiveDirectory, archiveName(state.branch));
  fileIO.write(archiveFile, handoff);

  // 6 — Build gate: must pass before the next session can start.
  // afterFixCommand has no registry-entry field yet, so it stays sourced
  // from the workspace config.json, defaulting to 'make rebuild'.
  final config = _loadConfig(fileIO, workspace);
  final build_ = buildFn ?? (command) => _defaultBuild(command, projectRoot, proc);
  print('\nRunning build gate: ${config.afterFixCommand}');
  final buildOk = await build_(config.afterFixCommand);
  if (!buildOk) {
    print('✗ Build failed. Fix the build before rotating.');
    print('  (gate: `${config.afterFixCommand}` — change it with "afterFixCommand" in ${configPathFor(workspace)})\n');
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

Future<bool> _defaultBuild(
  String command,
  String workingDirectory,
  ProcessRunner proc,
) async {
  final parts = command.split(' ');
  final result = await proc.run(
    parts.first,
    parts.skip(1).toList(),
    workingDirectory: workingDirectory,
  );
  return result.exitCode == 0;
}

String _truncate(String s, {int max = 72}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
