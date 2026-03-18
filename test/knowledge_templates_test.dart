import 'package:test/test.dart';
import 'package:claudart/knowledge_templates.dart';

void main() {
  // ── codeTemplate ─────────────────────────────────────────────────────────────

  group('codeTemplate', () {
    test('contains enum-first law heading', () {
      expect(codeTemplate, contains('## Enum-first law'));
    });

    test('enum-first law has Theory layer', () {
      expect(codeTemplate, contains('**Theory:**'));
    });

    test('enum-first law has Rule layer', () {
      expect(codeTemplate, contains('**Rule:** No bare string literals'));
    });

    test('enum-first law has security rationale', () {
      expect(codeTemplate, contains('compile-time constants'));
      expect(codeTemplate, contains('compiler rejects'));
    });

    test('contains parse-once rule heading', () {
      expect(codeTemplate, contains('## Parse-once rule'));
    });

    test('parse-once has O(n×k) complexity proof', () {
      expect(codeTemplate, contains('O(n×k)'));
    });

    test('parse-once Rule layer present', () {
      expect(codeTemplate, contains('Parse at the command entry point'));
    });

    test('contains three-layer explanation rule', () {
      expect(codeTemplate, contains('## Three-layer explanation rule'));
      expect(codeTemplate, contains('**Theory**'));
      expect(codeTemplate, contains('**Rule**'));
      expect(codeTemplate, contains('**Example**'));
    });

    test('contains enum capability decision table', () {
      expect(codeTemplate, contains('## Dart Enhanced Enums — capability table'));
      expect(codeTemplate, contains('Exhaustive switch'));
      expect(codeTemplate, contains('When-guard'));
      expect(codeTemplate, contains('Static factory'));
    });

    test('contains enum vs sealed vs record vs extension type table', () {
      expect(codeTemplate, contains('## When to use enum vs sealed class'));
      expect(codeTemplate, contains('`enum`'));
      expect(codeTemplate, contains('`sealed class`'));
      expect(codeTemplate, contains('`record`'));
      expect(codeTemplate, contains('`extension type`'));
    });

    test('does not contain Flutter or project-specific references', () {
      expect(codeTemplate, isNot(contains('Flutter')));
      expect(codeTemplate, isNot(contains('VolumeBloc')));
      expect(codeTemplate, isNot(contains('media_ivi')));
    });
  });

  // ── dartTemplate ─────────────────────────────────────────────────────────────

  group('dartTemplate', () {
    test('includes version tag', () {
      final t = dartTemplate('3.8.0');
      expect(t, contains('Dart 3.8.0'));
    });

    test('contains collection type decision table', () {
      final t = dartTemplate('3.x');
      expect(t, contains('## Collection type decision table'));
      expect(t, contains('HashMap'));
      expect(t, contains('LinkedHashMap'));
      expect(t, contains('SplayTreeMap'));
      expect(t, contains('O(1)'));
      expect(t, contains('O(log n)'));
    });

    test('collection table rule favours const Set for lookup', () {
      final t = dartTemplate('3.x');
      expect(t, contains('const Set'));
    });

    test('enum test matrix rule present', () {
      final t = dartTemplate('3.x');
      expect(t, contains('Enum test matrix rule'));
      expect(t, contains('enum.values × getters'));
    });

    test('when-guard syntax documented', () {
      final t = dartTemplate('3.x');
      expect(t, contains('when'));
    });

    test('isolate decision table present', () {
      final t = dartTemplate('3.x');
      expect(t, contains('## When to use isolates'));
      expect(t, contains('Isolate.run()'));
      expect(t, contains('Isolate.spawn()'));
      expect(t, contains('async/await'));
    });

    test('sealed class vs enum contrast present', () {
      final t = dartTemplate('3.x');
      expect(t, contains('Sealed class'));
      expect(t, contains('sealed class'));
    });

    test('records section present', () {
      final t = dartTemplate('3.x');
      expect(t, contains('## Records'));
    });

    test('general rules ban dynamic and late', () {
      final t = dartTemplate('3.x');
      expect(t, contains('dynamic'));
      expect(t, contains('late'));
      expect(t, contains('const'));
    });

    test('does not contain Flutter or BLoC references', () {
      final t = dartTemplate('3.x');
      expect(t, isNot(contains('Flutter')));
      expect(t, isNot(contains('BLoC')));
      expect(t, isNot(contains('bloc')));
    });
  });

  // ── testingTemplate ───────────────────────────────────────────────────────────

  group('testingTemplate', () {
    test('contains when-a-test-is-required heading', () {
      expect(testingTemplate, contains('## When a test is required'));
    });

    test('when-a-test-is-required lists public function change', () {
      expect(testingTemplate, contains('public function or method is added'));
    });

    test('when-a-test-is-required lists enum variant change', () {
      expect(testingTemplate, contains('enum gains a variant'));
    });

    test('contains coverage model heading', () {
      expect(testingTemplate, contains('## Coverage model'));
    });

    test('coverage model uses set notation T ⊇ C', () {
      expect(testingTemplate, contains('T ⊇ C'));
    });

    test('coverage model defines Gap = T − C', () {
      expect(testingTemplate, contains('Gap = T − C'));
    });

    test('coverage model session-done condition gap = ∅', () {
      expect(testingTemplate, contains('gap = ∅'));
    });

    test('contains enum test matrix rule heading', () {
      expect(testingTemplate, contains('## Enum test matrix rule'));
    });

    test('enum test matrix rule uses values × getters formula', () {
      expect(testingTemplate, contains('enum.values × getters'));
    });

    test('enum test matrix rule states every cell must have assertion', () {
      expect(testingTemplate, contains('Every cell must have an assertion'));
    });

    test('contains injectable interfaces heading', () {
      expect(testingTemplate, contains('## Injectable interfaces'));
    });

    test('injectable interfaces table lists FileIO', () {
      expect(testingTemplate, contains('FileIO'));
    });

    test('injectable interfaces table lists confirmFn', () {
      expect(testingTemplate, contains('confirmFn'));
    });

    test('injectable interfaces table lists exitFn', () {
      expect(testingTemplate, contains('exitFn'));
    });

    test('test structure rules require randomized ordering', () {
      expect(testingTemplate, contains('randomize-ordering-seed'));
    });

    test('test structure rules require one assertion per test', () {
      expect(testingTemplate, contains('One assertion per test'));
    });

    test('does not contain Flutter-specific sections', () {
      expect(testingTemplate, isNot(contains('## Widget tests')));
      expect(testingTemplate, isNot(contains('## Golden tests')));
    });
  });

  // ── projectTemplate ───────────────────────────────────────────────────────────

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

  // ── claudeMdTemplate ─────────────────────────────────────────────────────────

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

    test('workflow protocol enforces verify before commit', () {
      expect(base, contains('Verify'));
      expect(base, contains('Never commit before testing'));
    });

    test('git rules forbid pushing to remote', () {
      expect(base, contains('Never push to remote'));
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
