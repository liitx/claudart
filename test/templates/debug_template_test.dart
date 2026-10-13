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

    test('names each status by its on-disk wire value, line by line', () {
      const lines = [
        '- Handoff status must be `ready-for-debug` or `debug-in-progress`',
        '- If status is **NOT** `ready-for-debug` or `debug-in-progress`: '
            '**stop**.',
        '- If status is `ready-for-debug`:',
        '  - Update status to `debug-in-progress` and proceed.',
        '- If status is `debug-in-progress`: read `## Debug Progress` to '
            'orient before continuing.',
        '2. Set status to `needs-suggest`',
      ];
      for (final line in lines) {
        expect(template, contains(line));
      }
    });
  });
}
