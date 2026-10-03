import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Abstraction over Process.run.
/// Swap in [MockProcessRunner] in tests to avoid spawning real processes.
abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Like [run], but actually kills the child process on [timeout] instead
  /// of merely abandoning the `Future` — `Future.timeout()` on top of [run]
  /// stops *waiting*, it does not stop the process, so a hung subprocess
  /// (confirmed: a stalled `aws sts get-caller-identity` probing the EC2
  /// metadata service) keeps running as an orphan after the caller moves
  /// on. Throws [TimeoutException] when [timeout] elapses.
  Future<ProcessResult> runKillable(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  });
}

/// Production implementation backed by dart:io.
class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );

  @override
  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      Process.runSync(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );

  @override
  Future<ProcessResult> runKillable(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final stdoutDone = process.stdout.transform(utf8.decoder).join();
    final stderrDone = process.stderr.transform(utf8.decoder).join();

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      process.kill();
    });
    final exitCode = await process.exitCode;
    timer.cancel();

    if (timedOut) {
      throw TimeoutException(
        '$executable ${arguments.join(' ')} did not respond within ${timeout.inSeconds}s',
        timeout,
      );
    }
    return ProcessResult(process.pid, exitCode, await stdoutDone, await stderrDone);
  }
}
