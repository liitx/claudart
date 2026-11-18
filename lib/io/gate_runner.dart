// gate_runner.dart — the one way a gate command is run
//
// A gate is a shell command whose exit code decides whether work may go on:
// `debug` runs the workspace's `verificationCommand` before it records a fix as
// verified, and `rotate` runs `afterFixCommand` before it seeds the next
// handoff. They ask different questions at different points of the state
// machine (docs/topology/gates.md), but they run the command the same way, and
// both keep what it said: the exit code and the tail of its output, so the
// data to judge a gate is not lost.

import 'dart:io';

import 'process_runner.dart';

/// How many of the last lines of a gate's output are kept.
const int gateOutputTailLines = 20;

/// Which gate ran.
enum GateKind {
  /// `debug`'s check that a fix works, before it is recorded as verified.
  debugVerification,

  /// `rotate`'s build, before the next handoff is seeded.
  rotateBuild,
}

/// How a gate command ended.
class GateResult {
  const GateResult({
    required this.exitCode,
    required this.outputTail,
    required this.durationMs,
  });

  /// A gate that passed, for a caller that has nothing to report about it.
  const GateResult.passed()
      : exitCode = 0,
        outputTail = '',
        durationMs = 0;

  /// A gate that failed with [exitCode] and [outputTail].
  const GateResult.failed({this.exitCode = 1, this.outputTail = ''})
      : durationMs = 0;

  final int exitCode;

  /// The last [gateOutputTailLines] lines it wrote, standard output then
  /// standard error.
  final String outputTail;

  final int durationMs;

  /// Whether the gate passed: exit code 0.
  bool get passed => exitCode == 0;
}

String _text(Object? output) => output is String ? output : '${output ?? ''}';

String _tail(Object? standardOutput, Object? standardError) {
  final lines = [
    for (final part in [standardOutput, standardError])
      if (_text(part).trim().isNotEmpty) _text(part).trimRight(),
  ].join('\n').split('\n');
  return (lines.length <= gateOutputTailLines
          ? lines
          : lines.sublist(lines.length - gateOutputTailLines))
      .join('\n');
}

/// A failure to start the command at all: it did not run, so it did not pass.
GateResult _couldNotStart(ProcessException error, int durationMs) => GateResult(
      exitCode: error.errorCode == 0 ? 127 : error.errorCode,
      outputTail: error.message,
      durationMs: durationMs,
    );

GateResult _resultOf(ProcessResult result, int durationMs) => GateResult(
      exitCode: result.exitCode,
      outputTail: _tail(result.stdout, result.stderr),
      durationMs: durationMs,
    );

/// Runs [command] through the shell in [workingDirectory]. [clock] is the time
/// it reads to measure the run, the wall clock when null.
Future<GateResult> runGate(
  ProcessRunner runner,
  String command,
  String workingDirectory, {
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final started = now();
  int elapsed() => now().difference(started).inMilliseconds;
  try {
    final result = await runner.run(
      shellExecutable,
      [shellCommandFlag, command],
      workingDirectory: workingDirectory,
    );
    return _resultOf(result, elapsed());
  } on ProcessException catch (error) {
    return _couldNotStart(error, elapsed());
  }
}

/// [runGate], blocking: for a caller inside code that is not asynchronous.
GateResult runGateSync(
  ProcessRunner runner,
  String command,
  String workingDirectory, {
  DateTime Function()? clock,
}) {
  final now = clock ?? DateTime.now;
  final started = now();
  int elapsed() => now().difference(started).inMilliseconds;
  try {
    final result = runner.runSync(
      shellExecutable,
      [shellCommandFlag, command],
      workingDirectory: workingDirectory,
    );
    return _resultOf(result, elapsed());
  } on ProcessException catch (error) {
    return _couldNotStart(error, elapsed());
  }
}
