import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../config/paths.dart';
import '../io/process_runner.dart';
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../io/process_exit.dart';

/// Runs an experiment: executes [command] with [args], tees stdout/stderr to a
/// dated `.ansi` log in the project's `experiments/` directory, and prints the
/// combined output to the terminal in real time.
///
/// Usage:  `claudart experiment <name> -- <command> [args...]`
///
/// Example:
///   `claudart experiment menu-colors -- dart run bin/claudart.dart`
///
/// Log written to:  `<workspace>/experiments/<name>_<timestamp>.ansi`
Future<void> runExperiment(
  List<String> args, {
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exitProcess;

  // ── Parse arguments: <name> -- <command> [args...] ────────────────────────
  final sepIdx = args.indexOf('--');
  if (sepIdx < 1 || sepIdx == args.length - 1) {
    print(UserText.experimentUsageClaudartExperimentNameCommandArgs.template);
    exit_(1);
  }
  final name = args.first;
  final cmdArgs = args.sublist(sepIdx + 1);

  // ── Resolve workspace ──────────────────────────────────────────────────────
  final entry = lookupProject(
    CommandSeams(io: fileIO, projectRootOverride: projectRootOverride),
  )?.entry;
  final experimentsDir =
      experimentsDirFor(entry?.workspacePath ?? workspacesRoot);

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
  stdout.writeln('\n▶  Experiment: $name');
  stdout.writeln('   Command  : ${cmdArgs.join(' ')}');
  stdout.writeln('   Log      : $logFile\n');
  await stdout.flush();

  final sw = Stopwatch()..start();

  // inheritStdio: child shares the terminal directly — no piping through the
  // parent IOSink. Required for interactive commands (raw stdin, arrow keys)
  // and ensures header/footer print in correct order.
  final process = await const RealProcessRunner().start(
    cmdArgs.first,
    cmdArgs.sublist(1),
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  sw.stop();

  // ── Write metadata log ─────────────────────────────────────────────────────
  // Raw ANSI output is not captured when inheriting stdio; the log records
  // run metadata. To capture output use shell: `<cmd> | tee output.ansi`
  final meta = '# Experiment: $name\n'
      '# Command  : ${cmdArgs.join(' ')}\n'
      '# Started  : $ts\n'
      '# Duration : ${sw.elapsedMilliseconds}ms\n'
      '# Exit code: $exitCode\n';
  fileIO.write(logFile, meta);

  stdout.writeln('\n✓ Experiment complete — ${sw.elapsedMilliseconds}ms  (exit $exitCode)');
  stdout.writeln('  Log: $logFile\n');
  await stdout.flush();

  if (exitCode != 0) exit_(exitCode);
}
