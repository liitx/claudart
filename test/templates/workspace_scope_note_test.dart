import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/templates/workspace_scope_note.dart';
import 'package:test/test.dart';

// Every slash command tells its agent which workspace it is for and how to see
// the others, and the baked-path flows pass --project to the claudart CLI so the
// CLI acts on the same workspace as the file paths, wherever the agent's
// current directory is.

void main() {
  const project = 'my-app';

  group('workspaceScopeNote', () {
    test('names the workspace, how to list the others, and the two rules', () {
      expect(
        workspaceScopeNote(project),
        '> **Scope:** this session is for the workspace **my-app**. To see '
        'the other linked workspaces and where their sessions stand, run '
        '`claudart workspaces` (add `--json` for a machine-readable list). '
        'Never edit another workspace\'s `handoff.md` by hand; to work there, '
        'open its repo or pass `claudart --project <name> <command>`.',
      );
    });

    test('a different project name changes only the name', () {
      expect(
        workspaceScopeNote('other-app'),
        workspaceScopeNote(project).replaceFirst('my-app', 'other-app'),
      );
    });
  });

  group('every command-bearing flow carries the note', () {
    for (final flow in AgentFlow.values.where((f) => f.hasCommandFile)) {
      test(flow.name, () {
        final template = flow.commandTemplate('/workspaces/my-app', project);
        expect(template, contains(workspaceScopeNote(project)));
        expect(
          RegExp(RegExp.escape(workspaceScopeNote(project)))
              .allMatches(template),
          hasLength(1),
          reason: 'once, not repeated',
        );
      });
    }
  });

  group('baked-path flows pass --project to the claudart CLI', () {
    // Independent literal: the CLI invocation each baked-path flow tells the
    // agent to run.
    const cliCalls = <AgentFlow, String>{
      AgentFlow.suggest: 'claudart preflight test --project my-app',
      AgentFlow.debug: 'claudart preflight debug --project my-app',
      AgentFlow.save: 'claudart save --project my-app',
      AgentFlow.teardown: 'claudart teardown --project my-app',
    };

    for (final entry in cliCalls.entries) {
      test('${entry.key.name}: ${entry.value}', () {
        final template = entry.key.commandTemplate('/workspaces/my-app', project);
        expect(template, contains(entry.value));
      });
    }

    test('the runtime-resolved flows (setup, flow) do not: they ask '
        '`claudart status` for the workspace of the current directory', () {
      for (final flow in [AgentFlow.setup, AgentFlow.flow]) {
        final template = flow.commandTemplate('/workspaces/my-app', project);
        expect(template, contains('claudart status'));
        expect(template, isNot(contains('--project my-app')));
      }
    });
  });
}
