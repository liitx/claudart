import 'package:test/test.dart';
import 'package:claudart/templates/teardown_template.dart';

void main() {
  group('teardownCommandTemplate', () {
    test('points generic knowledge one level above the workspace dir', () {
      final template = teardownCommandTemplate('/workspace', 'my-app');
      expect(template, contains('/workspace/../knowledge/generic/'));
      expect(template, isNot(contains('/workspace/knowledge/generic/')));
    });
  });
}
