import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';

/// Runs an experiment: executes [command] with [args], tees stdout/stderr to a
/// dated `.ansi` log in the project's `experiments/` directory, and prints the
/// combined output to the terminal in real time.
///
/// Usage:  claudart experiment <name> -- <command> [args...]
///
/// Example:
///   claudart experiment menu-colors -- dart run bin/claudart.dart
///
/// Log written to:  <workspace>/experiments/<name>_<timestamp>.ansi
Future<void> runExperiment(
  List<String> args, {
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;

  // ── Parse arguments: <name> -- <command> [args...] ────────────────────────
  final sepIdx = args.indexOf('--');
  if (sepIdx < 1 || sepIdx == args.length - 1) {
    print('Usage: claudart experiment <name> -- <command> [args...]');
    exit_(1);
  }
  final name = args.first;
  final cmdArgs = args.sublist(sepIdx + 1);

  // ── Resolve workspace ──────────────────────────────────────────────────────
  final projectRoot = projectRootOverride ?? detectGitContext()?.root;
  String experimentsDir;
  if (projectRoot != null) {
    final registry = Registry.load(io: fileIO);
    final entry = registry.findByProjectRoot(projectRoot);
    experimentsDir = entry != null
        ? experimentsDirFor(entry.workspacePath)
        : experimentsDirFor(workspacesRoot);
  } else {
    experimentsDir = experimentsDirFor(workspacesRoot);
  }

  // ── Build log file path ────────────────────────────────────────────────────
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  fileIO.createDir(experimentsDir);
  final logFile = p.join(experimentsDir, '${safeName}_$ts.ansi');

  // ── Run command, tee output ────────────────────────────────────────────────
  print('\n▶  Experiment: $name');
  print('   Command  : ${cmdArgs.join(' ')}');
  print('   Log      : $logFile\n');

  final sw = Stopwatch()..start();
  final process = await Process.start(
    cmdArgs.first,
    cmdArgs.sublist(1),
    runInShell: false,
  );

  final logBuffer = StringBuffer();

  // Mirror stdout.
  process.stdout.listen((bytes) {
    final text = String.fromCharCodes(bytes);
    stdout.write(text);
    logBuffer.write(text);
  });

  // Mirror stderr.
  process.stderr.listen((bytes) {
    final text = String.fromCharCodes(bytes);
    stderr.write(text);
    logBuffer.write(text);
  });

  final exitCode = await process.exitCode;
  sw.stop();

  // ── Write log ──────────────────────────────────────────────────────────────
  final header = '# Experiment: $name\n'
      '# Command  : ${cmdArgs.join(' ')}\n'
      '# Started  : $ts\n'
      '# Duration : ${sw.elapsedMilliseconds}ms\n'
      '# Exit code: $exitCode\n\n';
  fileIO.write(logFile, header + logBuffer.toString());

  print('\n✓ Experiment complete — ${sw.elapsedMilliseconds}ms  (exit $exitCode)');
  print('  Log: $logFile\n');

  if (exitCode != 0) exit_(exitCode);
}
