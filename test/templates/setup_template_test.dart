import 'package:test/test.dart';
import 'package:claudart/templates/setup_template.dart';

void main() {
  group('setupCommandTemplate', () {
    final template = setupCommandTemplate('/workspace', 'my-app');

    test('includes the project name in the description header', () {
      expect(template, contains('description: Compile workspace scaffold — my-app'));
    });

    test('points generic knowledge one level above the workspace dir, not two', () {
      // <workspace_dir> is `<workspacesRoot>/<project>` — one `..` reaches
      // workspacesRoot, where knowledge/generic/ actually lives. A second
      // `..` overshoots into workspacesRoot's own parent, where the
      // directory doesn't exist — confirmed live against a real registry
      // entry; this was silently wrong before.
      expect(
        template,
        contains(r'<workspace_dir>/../knowledge/generic/<name>.md'),
      );
      expect(
        template,
        isNot(contains(r'<workspace_dir>/../../knowledge/generic/<name>.md')),
      );
    });
  });
}
