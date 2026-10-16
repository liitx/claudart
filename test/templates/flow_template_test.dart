import 'package:claudart/templates/flow_template.dart';
import 'package:test/test.dart';

void main() {
  group('flowCommandTemplate', () {
    final template = flowCommandTemplate('/workspace', 'my-app');

    test('the construct step names the starting status by its wire value', () {
      expect(template, contains('- Status: suggest-investigating\n'));
    });

    test('tells the agent which status to write, by its wire value', () {
      expect(
        template,
        contains(
          'Flip status to `ready-for-debug` if implementing; '
          'keep `suggest-investigating` if exploring.',
        ),
      );
    });
  });
}
