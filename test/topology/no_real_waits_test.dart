// No real waiting in tests: a test that needs time to pass advances a fake
// clock (`fake_async`) or is given the time through a seam (`CommandSeams.clock`).
// A real wait makes a suite slow, and a test that depends on one is only as
// reliable as the machine's speed.

import 'dart:io';

import 'package:test/test.dart';

/// A real wait: a delayed future, a timer, or a blocking sleep.
final _realWait = RegExp(r'\.delayed\(|\bTimer(\.periodic)?\(|\bsleep\(');

/// Files that wait on a real subprocess, whose clock no fake can advance.
const _realSubprocessLedger = {
  'test/process_runner_test.dart',
  'test/pipeline/default_claude_runner_timeout_test.dart',
};

/// The files that wait for real and neither fake the clock nor are ledgered.
List<String> realWaiters(Map<String, String> sources) => [
      for (final entry in sources.entries)
        if (!_realSubprocessLedger.contains(entry.key) &&
            !entry.value.contains('package:fake_async/') &&
            _realWait.hasMatch(entry.value))
          entry.key,
    ]..sort();

void main() {
  group('real waits in tests', () {
    test('a delayed future outside fakeAsync is found', () {
      expect(
        realWaiters({'test/a_test.dart': 'await Future<void>.delayed(d);'}),
        ['test/a_test.dart'],
      );
    });

    test('a file that fakes the clock is not found', () {
      expect(
        realWaiters({
          'test/a_test.dart': "import 'package:fake_async/fake_async.dart';\n"
              'await Future<void>.delayed(d);',
        }),
        isEmpty,
      );
    });

    test('a sleep and a timer are found', () {
      expect(realWaiters({'a': 'sleep(d);', 'b': 'Timer(d, f);'}), ['a', 'b']);
    });

    test('tests wait only on a fake clock, or on a real subprocess', () {
      final sources = {
        for (final file in Directory('test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
      };
      expect(realWaiters(sources), isEmpty);
    });
  });
}
