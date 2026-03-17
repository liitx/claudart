import 'package:test/test.dart';
import 'package:claudart/knowledge_templates.dart';

void main() {
  group('dartTemplate', () {
    test('includes version tag', () {
      final t = dartTemplate('3.8.0');
      expect(t, contains('Dart 3.8.0'));
    });

    test('contains core practices', () {
      final t = dartTemplate('3.x');
      expect(t, contains('const'));
      expect(t, contains('sealed'));
    });

    test('does not contain Flutter or BLoC references', () {
      final t = dartTemplate('3.x');
      expect(t, isNot(contains('Flutter')));
      expect(t, isNot(contains('BLoC')));
      expect(t, isNot(contains('bloc')));
    });
  });

  group('testingTemplate', () {
    test('contains key headings', () {
      expect(testingTemplate, contains('## Unit tests'));
      expect(testingTemplate, contains('## Coverage'));
    });

    test('does not contain Flutter-specific sections', () {
      expect(testingTemplate, isNot(contains('## Widget tests')));
      expect(testingTemplate, isNot(contains('## Golden tests')));
    });
  });

  group('projectTemplate', () {
    test('includes project name', () {
      final t = projectTemplate('my-app');
      expect(t, contains('my-app'));
    });

    test('contains expected sections', () {
      final t = projectTemplate('x');
      expect(t, contains('## Architecture'));
      expect(t, contains('## Hot paths'));
      expect(t, contains('## Root cause patterns'));
      expect(t, contains('## Anti-patterns'));
    });
  });

  group('claudeMdTemplate', () {
    final base = claudeMdTemplate(
      workspacePath: '/workspace',
      projectName: 'my-app',
      genericFiles: ['dart.md', 'testing.md'],
    );

    test('includes project name', () {
      expect(base, contains('Project: my-app'));
    });

    test('lists generic knowledge files with absolute paths', () {
      expect(base, contains('/workspace/knowledge/generic/dart.md'));
      expect(base, contains('/workspace/knowledge/generic/testing.md'));
    });

    test('includes project knowledge path', () {
      expect(base, contains('/workspace/knowledge/projects/my-app.md'));
    });

    test('includes session state paths', () {
      expect(base, contains('/workspace/handoff.md'));
      expect(base, contains('/workspace/skills.md'));
    });

    test('no environment section when constraints absent', () {
      expect(base, isNot(contains('## Environment')));
    });

    test('includes environment section when sdk provided', () {
      final t = claudeMdTemplate(
        workspacePath: '/workspace',
        projectName: 'my-app',
        genericFiles: [],
        sdkConstraint: '^3.8.0',
      );
      expect(t, contains('## Environment'));
      expect(t, contains('Dart SDK: `^3.8.0`'));
    });

    test('includes flutter constraint when provided', () {
      final t = claudeMdTemplate(
        workspacePath: '/workspace',
        projectName: 'my-app',
        genericFiles: [],
        sdkConstraint: '^3.8.0',
        flutterConstraint: '3.32.5',
      );
      expect(t, contains('Flutter: `3.32.5`'));
    });

    test('includes analyzer instruction in environment section', () {
      final t = claudeMdTemplate(
        workspacePath: '/workspace',
        projectName: 'my-app',
        genericFiles: [],
        sdkConstraint: '^3.8.0',
      );
      expect(t, contains('Do not suggest APIs or syntax unavailable'));
    });
  });
}
