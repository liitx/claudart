import 'package:claudart/pipeline/agent_flow.dart';
import 'package:test/test.dart';

void main() {
  group('AgentFlow.steps', () {
    const withSteps = {
      AgentFlow.suggest,
      AgentFlow.debug,
      AgentFlow.teardown,
      AgentFlow.flow,
    };

    for (final flow in AgentFlow.values) {
      final has = withSteps.contains(flow);
      test('${flow.name}: steps are ${has ? 'non-empty' : 'empty'}', () {
        expect(flow.steps.isNotEmpty, has);
      });
    }
  });

  group('hasCommandFile and commandTemplate', () {
    const withCommandFile = {
      AgentFlow.suggest,
      AgentFlow.debug,
      AgentFlow.setup,
      AgentFlow.save,
      AgentFlow.teardown,
      AgentFlow.flow,
    };

    for (final flow in AgentFlow.values) {
      final has = withCommandFile.contains(flow);
      test('${flow.name}: hasCommandFile is $has', () {
        expect(flow.hasCommandFile, has);
      });

      test('${flow.name}: its template is ${has ? 'non-empty' : 'empty'}', () {
        final template = flow.commandTemplate('/workspace', 'my-app');
        expect(template.isNotEmpty, has);
      });
    }
  });

  group('names', () {
    for (final flow in AgentFlow.values) {
      test('${flow.name}: cliArgs, fileName, legacyFileName, value', () {
        expect(flow.cliArgs, ['claudart', flow.name]);
        expect(flow.fileName('my-app'), '${flow.name}-my-app.md');
        expect(flow.legacyFileName, '${flow.name}.md');
        expect(flow.value, flow.name);
        expect(AgentFlow.fromString(flow.value), flow);
      });
    }

    test('a literal example: suggest', () {
      expect(AgentFlow.suggest.cliArgs, ['claudart', 'suggest']);
      expect(AgentFlow.suggest.fileName('my-app'), 'suggest-my-app.md');
      expect(AgentFlow.suggest.legacyFileName, 'suggest.md');
    });

    test('fromString: an unknown name is null', () {
      expect(AgentFlow.fromString('nonsense'), isNull);
      expect(AgentFlow.fromString(''), isNull);
    });
  });

  group('fromSlashCommand', () {
    const withSlashCommand = {
      AgentFlow.suggest,
      AgentFlow.debug,
      AgentFlow.setup,
      AgentFlow.save,
      AgentFlow.teardown,
      AgentFlow.flow,
      AgentFlow.research,
    };

    for (final flow in AgentFlow.values) {
      final has = withSlashCommand.contains(flow);
      test('/${flow.name} -> ${has ? flow.name : 'null'}', () {
        expect(flow.hasSlashCommand, has);
        expect(
          AgentFlow.fromSlashCommand('/${flow.name}'),
          has ? flow : isNull,
        );
      });

      test('${flow.name} without the slash is null', () {
        expect(AgentFlow.fromSlashCommand(flow.name), isNull);
      });
    }

    test('an empty or unknown command is null', () {
      expect(AgentFlow.fromSlashCommand(''), isNull);
      expect(AgentFlow.fromSlashCommand('/nonsense'), isNull);
    });
  });
}
