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

    final exitCode = await process.exitCode.timeout(timeout, onTimeout: () async {
      // Killing just [process] leaves any child it spawned (confirmed
      // real: `aws`'s own `credential_process` helper, e.g. `pybritive`)
      // as an orphan — `process.kill()` only ever reaches the direct
      // child, never its descendants. Walk and kill the whole subtree
      // first, and await it, so nothing outlives this call returning.
      await killProcessTree(process.pid);
      process.kill(ProcessSignal.sigkill);
      throw TimeoutException(
        '$executable ${arguments.join(' ')} did not respond within ${timeout.inSeconds}s',
        timeout,
      );
    });
    return ProcessResult(process.pid, exitCode, await stdoutDone, await stderrDone);
  }
}

/// Kills every descendant of [pid] (children, grandchildren, ...),
/// deepest first, via `pgrep -P`/`kill -9` — `dart:io` has no built-in
/// process-group kill. Unix-only (`pgrep` isn't available on Windows),
/// matching this project's existing Unix-only assumptions. Best-effort:
/// a `pgrep`/`kill` failure (process already gone, tool missing) is
/// swallowed rather than thrown, since this always runs alongside a kill
/// of the direct child that must not be blocked by it.
Future<void> killProcessTree(int pid) async {
  for (final child in await _childPids(pid)) {
    await killProcessTree(child);
    try {
      await Process.run('kill', ['-9', '$child']);
    } on ProcessException {
      // `kill` itself unavailable — nothing to do.
    }
  }
}

Future<List<int>> _childPids(int pid) async {
  try {
    final result = await Process.run('pgrep', ['-P', '$pid']);
    if (result.exitCode != 0) return const [];
    return (result.stdout as String)
        .split('\n')
        .map((line) => int.tryParse(line.trim()))
        .whereType<int>()
        .toList();
  } on ProcessException {
    return const [];
  }
}
