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
  });
}
