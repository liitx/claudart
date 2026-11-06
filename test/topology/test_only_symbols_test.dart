// A symbol that only tests read is a proof of nothing (gap T1): the Q4 proofs
// passed over `listenersFor` while no runtime code consulted it. The census in
// `tool/check_test_only_symbols.dart` names such symbols; this makes it a gate:
// the count may only go down.

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/check_test_only_symbols.dart';

/// The symbols that only tests read, today. Each is older than the ratchet and
/// is tracked, not hidden; a new one fails the build.
const _knownTestOnlySymbols = 12;

Map<String, String> _readSources() => {
      for (final root in ['lib', 'bin', 'tool', 'test'])
        if (Directory(root).existsSync())
          for (final file in Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
            file.path: file.readAsStringSync(),
    };

void main() {
  group('test-only symbols', () {
    test('a function only a test calls is found', () {
      final found = testOnlySymbols({
        'lib/a.dart': 'bool decide(int x) {\n  return x > 0;\n}\n',
        'test/a_test.dart': 'void main() { decide(1); }',
      });
      expect(found, ['decide (lib/a.dart)']);
    });

    test('a function that other lib code calls is not found', () {
      final found = testOnlySymbols({
        'lib/a.dart': 'bool decide(int x) {\n  return x > 0;\n}\n',
        'lib/b.dart': 'final ok = decide(1);',
        'test/a_test.dart': 'void main() { decide(1); }',
      });
      expect(found, isEmpty);
    });

    test('a function a tool script calls is not found, a tool is real use', () {
      final found = testOnlySymbols({
        'lib/a.dart': 'bool decide(int x) {\n  return x > 0;\n}\n',
        'tool/draw.dart': 'void main() { decide(1); }',
        'test/a_test.dart': 'void main() { decide(1); }',
      });
      expect(found, isEmpty);
    });

    test('a function that nothing calls is not found, it is dead, not test-only',
        () {
      final found = testOnlySymbols({
        'lib/a.dart': 'bool decide(int x) {\n  return x > 0;\n}\n',
      });
      expect(found, isEmpty);
    });

    test('a symbol the barrel exports is public API, not found', () {
      final found = testOnlySymbols({
        'lib/claudart.dart': "export 'a.dart' show decide;",
        'lib/a.dart': 'bool decide(int x) {\n  return x > 0;\n}\n',
        'test/a_test.dart': 'void main() { decide(1); }',
      });
      expect(found, isEmpty);
    });

    test('symbols that only tests read do not grow', () {
      final found = testOnlySymbols(_readSources());
      expect(
        found.length,
        lessThanOrEqualTo(_knownTestOnlySymbols),
        reason: 'a lib symbol that only tests read proves nothing about the '
            'system: wire it into the code, or delete it. Found: $found',
      );
    });
  });
}
