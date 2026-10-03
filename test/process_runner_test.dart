// process_runner_test.dart — RealProcessRunner.runKillable, hit with real
// subprocesses per dartrix's testing paradigm ("hit real subprocesses with
// inheritStdio" — a fake process can't prove a real kill signal reaches a
// real grandchild).

import 'dart:async';
import 'dart:io';

import 'package:claudart/process_runner.dart';
import 'package:test/test.dart';

/// True while a process with [pid] is still alive. `kill -0` sends no
/// signal, just checks the pid exists — portable across macOS/Linux.
bool _isAlive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  group('RealProcessRunner.run', () {
    test('passes environment through to the subprocess', () async {
      final result = await const RealProcessRunner().run(
        'sh',
        ['-c', 'echo \$CLAUDART_TEST_VAR'],
        environment: {'CLAUDART_TEST_VAR': 'present'},
      );
      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), equals('present'));
    });
  });

  group('RealProcessRunner.runKillable', () {
    test('returns normally when the process completes before the timeout', () async {
      final result = await const RealProcessRunner().runKillable(
        'sh',
        ['-c', 'echo done'],
        timeout: const Duration(seconds: 5),
      );
      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), equals('done'));
    });

    test('throws TimeoutException and kills a real grandchild, not just the direct child', () async {
      final pidFile = '${Directory.systemTemp.path}/claudart_test_grandchild_pid_${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() {
        final f = File(pidFile);
        if (f.existsSync()) f.deleteSync();
      });

      // The direct child (`sh`) spawns a background grandchild (`sleep`)
      // and then blocks on it with `wait` — same shape as `aws` spawning a
      // `credential_process` helper and hanging on its result. Killing
      // only the direct child would leave `sleep 100` running as an
      // orphan, exactly the bug this test guards against.
      final script = 'sleep 100 & echo \$! > $pidFile; wait';

      await expectLater(
        const RealProcessRunner().runKillable(
          'sh',
          ['-c', script],
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // Give the kill a moment to actually land before checking.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final pidText = await File(pidFile).readAsString();
      final grandchildPid = int.parse(pidText.trim());
      expect(
        _isAlive(grandchildPid),
        isFalse,
        reason: 'grandchild pid $grandchildPid should have been killed with the rest of the tree',
      );
    });
  });
}
