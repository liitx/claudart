import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:test/test.dart';

// claudart owns AgentFlow.preferredModel, so claudart tests it. This literal
// table pins today's static routing (issue #87 plans to replace it with a
// benchmarked classification); consumers use it and do not re-assert it.

const _preferred = <AgentFlow, AgentModel?>{
  AgentFlow.suggest: AgentModel.opus,
  AgentFlow.debug: AgentModel.sonnet,
  AgentFlow.setup: AgentModel.haiku,
  AgentFlow.save: AgentModel.haiku,
  AgentFlow.teardown: AgentModel.haiku,
  AgentFlow.flow: AgentModel.sonnet,
  AgentFlow.research: AgentModel.haiku,
  AgentFlow.free: AgentModel.sonnet,
  AgentFlow.cli: null,
  AgentFlow.guiDesign: AgentModel.opus,
};

void main() {
  test('the table covers every flow', () {
    expect(_preferred.keys.toSet(), AgentFlow.values.toSet());
  });

  group('AgentFlow.preferredModel', () {
    for (final entry in _preferred.entries) {
      test('${entry.key.name}: ${entry.value?.name ?? 'none (cli)'}', () {
        expect(entry.key.preferredModel, entry.value);
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
    const slash = {
      '/suggest': AgentFlow.suggest,
      '/debug': AgentFlow.debug,
      '/setup': AgentFlow.setup,
      '/save': AgentFlow.save,
      '/teardown': AgentFlow.teardown,
      '/flow': AgentFlow.flow,
      '/research': AgentFlow.research,
    };

    for (final entry in slash.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(AgentFlow.fromSlashCommand(entry.key), entry.value);
      });
    }

    test('without the slash, or unknown, is null', () {
      expect(AgentFlow.fromSlashCommand('suggest'), isNull);
      expect(AgentFlow.fromSlashCommand('/free'), isNull);
      expect(AgentFlow.fromSlashCommand('/cli'), isNull);
      expect(AgentFlow.fromSlashCommand(''), isNull);
    });
  });
}
