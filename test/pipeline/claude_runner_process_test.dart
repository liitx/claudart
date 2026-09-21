// claude_runner_process_test.dart — a child that fills the stderr pipe
// while stdout stays open must not hang the runner forever. Drains both
// streams concurrently and enforces a timeout with a real kill.

import 'dart:io';

import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'drainProcess returns once a stderr-heavy child exits, without hanging',
    () async {
      // Writes ~200KB to stderr (well past the ~64KiB OS pipe buffer) before
      // closing stdout. A sequential stdout-then-stderr drain would hang here.
      final process = await Process.start(
        'sh',
        ['-c', 'yes x | head -c 200000 >&2; echo out'],
      );

      final drained = await drainProcess(
        process,
        timeout: const Duration(seconds: 10),
      );

      expect(drained.timedOut, isFalse);
      expect(drained.exitCode, equals(0));
      expect(drained.stdoutLines, contains('out'));
      expect(drained.stderr.length, greaterThan(100000));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'drainProcess kills a hung child and reports timedOut',
    () async {
      final process = await Process.start('sh', ['-c', 'sleep 30']);

      final drained = await drainProcess(
        process,
        timeout: const Duration(milliseconds: 300),
      );

      expect(drained.timedOut, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
