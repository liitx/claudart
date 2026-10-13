import 'package:test/test.dart';
import 'package:claudart/templates/suggest_template.dart';

void main() {
  group('suggestCommandTemplate', () {
    final template = suggestCommandTemplate('/workspace', 'my-app');

    test('points generic knowledge one level above the workspace dir, with the real filenames', () {
      // knowledge/generic/ is shared/root-level, one `..` up from the
      // per-project workspace dir — confirmed live against the real
      // directory; `dart.md` was also never the real filename
      // (`dart_flutter.md` is).
      expect(template, contains('/workspace/../knowledge/generic/dart_flutter.md'));
      expect(template, contains('/workspace/../knowledge/generic/testing.md'));
      expect(template, isNot(contains('/workspace/knowledge/generic/dart.md')));
    });

    test('knowledge/projects/ stays workspace-scoped, no ../ needed', () {
      expect(template, contains('/workspace/knowledge/projects/<project-name>.md'));
    });

    test('status routing names each status as its on-disk wire value, one route per line', () {
      expect(template, contains('- `needs-suggest`: read **Debug Progress** first'));
      expect(template, contains('- `ready-for-suggest` or `suggest-investigating`: proceed to Step 2.'));
      expect(template, contains('- `ready-for-debug` or `debug-in-progress`: ask "This looks ready for `/debug` — re-run `/suggest` and overwrite the existing KT anyway?"'));
    });

    test('the write steps name the target status as its wire value', () {
      expect(template, contains('2. Set status to `ready-for-debug`'));
      expect(template, contains('If status was `needs-suggest`:'));
      expect(template, contains('4. Write `## Suggest Resume Notes`, flip status to `ready-for-debug`'));
    });
  });
}
