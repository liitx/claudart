import 'package:claudart/templates/save_template.dart';
import 'package:test/test.dart';

void main() {
  group('saveCommandTemplate', () {
    final template = saveCommandTemplate('/workspace', 'my-app');

    test('the next-step table names each status by its wire value', () {
      // One contiguous block: the row boundaries are part of the table.
      expect(
        template,
        contains(
          '| Status                    | Next step                        '
          '                |\n'
          '|---------------------------|----------------------------------'
          '----------------|\n'
          '| `suggest-investigating`   | Continue exploring. '
          'Run `/save` when root cause confirmed. |\n'
          '| `ready-for-debug`         | Root cause locked. '
          'Run `/debug` to implement the fix. |\n'
          '| `debug-in-progress`       | Fix in progress. '
          'Run `/save` again after fix confirmed. |',
        ),
      );
    });
  });
}
