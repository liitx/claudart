import 'package:test/test.dart';
import 'package:claudart/templates/debug_template.dart';

void main() {
  group('debugCommandTemplate', () {
    final template = debugCommandTemplate('/workspace', 'my-app');

    test('points generic knowledge one level above the workspace dir, with the real filenames', () {
      expect(template, contains('/workspace/../knowledge/generic/dart_flutter.md'));
      expect(template, contains('/workspace/../knowledge/generic/testing.md'));
      expect(template, isNot(contains('/workspace/knowledge/generic/dart.md')));
    });
  });
}
