import 'package:test/test.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/commands/suggest_template.dart';
import 'package:claudart/commands/debug_template.dart';
import 'package:claudart/commands/setup_template.dart';
import 'package:claudart/commands/teardown_template.dart';

// A per-project workspace, distinct from workspacesRoot — this is what
// `claudart link` actually passes as workspacePath.
final String _workspace = workspaceFor('my-app');

void main() {
  group('suggestCommandTemplate knowledge paths', () {
    final t = suggestCommandTemplate(_workspace, 'my-app');

    test('references the shared generic knowledge dir init writes to', () {
      expect(t, contains('$genericKnowledgeDir/dart.md'));
      expect(t, contains('$genericKnowledgeDir/testing.md'));
    });

    test('references the shared projects knowledge dir', () {
      expect(t, contains(projectsKnowledgeDir));
    });

    test('does not point at knowledge under the per-project workspace', () {
      expect(t, isNot(contains('$_workspace/knowledge')));
    });
  });

  group('debugCommandTemplate knowledge paths', () {
    final t = debugCommandTemplate(_workspace, 'my-app');

    test('references the shared generic knowledge dir init writes to', () {
      expect(t, contains('$genericKnowledgeDir/dart.md'));
      expect(t, contains('$genericKnowledgeDir/testing.md'));
    });

    test('references the shared projects knowledge dir', () {
      expect(t, contains(projectsKnowledgeDir));
    });

    test('does not point at knowledge under the per-project workspace', () {
      expect(t, isNot(contains('$_workspace/knowledge')));
    });
  });

  group('setupCommandTemplate knowledge paths', () {
    final t = setupCommandTemplate(_workspace, 'my-app');

    test('references the shared generic knowledge dir init writes to', () {
      expect(t, contains(genericKnowledgeDir));
    });

    test('does not resolve via ../.. from the workspace dir', () {
      expect(t, isNot(contains('../../knowledge/generic')));
    });
  });

  group('teardownCommandTemplate knowledge paths', () {
    final t = teardownCommandTemplate(_workspace, 'my-app');

    test('references the shared generic knowledge dir init writes to', () {
      expect(t, contains(genericKnowledgeDir));
    });

    test('references the shared projects knowledge dir', () {
      expect(t, contains(projectsKnowledgeDir));
    });

    test('does not point at knowledge under the per-project workspace', () {
      expect(t, isNot(contains('$_workspace/knowledge')));
    });
  });
}
