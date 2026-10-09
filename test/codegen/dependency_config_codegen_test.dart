// dependency_config_codegen_test.dart — render + write, mirroring zedup's
// own user_config_codegen_test.dart style for the same pattern.

import 'package:claudart/codegen/dependency_config_codegen.dart';
import 'package:test/test.dart';

void main() {
  const codegen = DependencyConfigCodegen();

  group('render', () {
    test('emits the generated header banner', () {
      final source = codegen.render(usesDartrix: true);
      expect(source, contains(kDependencyConfigGeneratedHeader.trim()));
    });

    test('emits usesDartrix = true when detected', () {
      final source = codegen.render(usesDartrix: true);
      expect(source, contains('const bool usesDartrix = true;'));
    });

    test('emits usesDartrix = false when not detected', () {
      final source = codegen.render(usesDartrix: false);
      expect(source, contains('const bool usesDartrix = false;'));
    });
  });

  group('write', () {
    test('writes the rendered source to the expected relative path', () async {
      String? writtenPath;
      String? writtenContent;
      await codegen.write(
        usesDartrix: true,
        projectRoot: '/fake/project',
        writer: (path, content) async {
          writtenPath = path;
          writtenContent = content;
        },
      );
      expect(writtenPath, '/fake/project/$kDependencyConfigGeneratedRelativePath');
      expect(writtenContent, contains('const bool usesDartrix = true;'));
    });
  });
}
