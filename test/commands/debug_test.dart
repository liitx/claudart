// debug_test.dart — resolveEditPath sandbox guard.
//
// A model-supplied <EDIT_FILE path="..."> must resolve inside projectRoot.
// Absolute paths and `..` escapes are refused, never joined blindly.

import 'package:claudart/commands/debug.dart';
import 'package:test/test.dart';

const _root = '/home/user/project';

void main() {
  group('resolveEditPath', () {
    test('plain relative path resolves inside projectRoot', () {
      final resolved = resolveEditPath(_root, 'lib/example.dart');
      expect(resolved, equals('/home/user/project/lib/example.dart'));
    });

    test('parent-escape is refused', () {
      expect(resolveEditPath(_root, '../x'), isNull);
    });

    test('absolute path is refused', () {
      expect(resolveEditPath(_root, '/home/user/.ssh/authorized_keys'), isNull);
    });

    test('escape then re-descend is still refused', () {
      expect(resolveEditPath(_root, 'a/../../x'), isNull);
    });

    test('internal .. that stays inside projectRoot resolves', () {
      final resolved = resolveEditPath(_root, 'a/../b.dart');
      expect(resolved, equals('/home/user/project/b.dart'));
    });
  });
}
