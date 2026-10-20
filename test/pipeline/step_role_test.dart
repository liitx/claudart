// step_role_test.dart — which models and tools each pipeline step role may use.
//
// Haiku is the cheapest model and is not sufficient to reason or implement.
// It may only classify and read; reasoning and implementation run on sonnet
// or opus. One test per (role, model) cell and per (role, tool) cell, so a
// changed permission fails by name.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/step_role.dart';
import 'package:test/test.dart';

/// The specification: every role with the models it may run on. Written out
/// by hand so the test is a spec, not a copy of the production switch.
const Map<StepRole, Set<AgentModel>> _permittedModelsByRole = {
  StepRole.classification: {
    AgentModel.haiku,
    AgentModel.sonnet,
    AgentModel.opus,
    AgentModel.fable,
  },
  StepRole.fileReading: {
    AgentModel.haiku,
    AgentModel.sonnet,
    AgentModel.opus,
    AgentModel.fable,
  },
  StepRole.reasoning: {AgentModel.sonnet, AgentModel.opus},
  StepRole.implementation: {AgentModel.sonnet, AgentModel.opus},
};

/// The specification: every role with the tools it may use. Written out by
/// hand. No role may write: implementation returns its plan as output.
const Map<StepRole, Set<ClaudeTool>> _allowedToolsByRole = {
  StepRole.classification: {},
  StepRole.fileReading: {ClaudeTool.read, ClaudeTool.glob, ClaudeTool.grep},
  StepRole.reasoning: {ClaudeTool.read, ClaudeTool.glob, ClaudeTool.grep},
  StepRole.implementation: {
    ClaudeTool.read,
    ClaudeTool.glob,
    ClaudeTool.grep,
  },
};

void main() {
  group('StepRole.permits', () {
    for (final role in StepRole.values) {
      for (final model in AgentModel.values) {
        final expected = _permittedModelsByRole[role]!.contains(model);
        test('${role.name} x ${model.name} -> $expected', () {
          expect(role.permits(model), equals(expected));
        });
      }
    }
  });

  group('StepRole.permittedModels', () {
    for (final role in StepRole.values) {
      test(role.name, () {
        expect(role.permittedModels, equals(_permittedModelsByRole[role]));
      });
    }
  });

  group('haiku never reasons or implements', () {
    for (final role in [StepRole.reasoning, StepRole.implementation]) {
      test(role.name, () {
        expect(role.permits(AgentModel.haiku), isFalse);
      });
    }
  });

  group('StepRole.allowedTools', () {
    for (final role in StepRole.values) {
      for (final tool in ClaudeTool.values) {
        final expected = _allowedToolsByRole[role]!.contains(tool);
        test('${role.name} x ${tool.name} -> $expected', () {
          expect(role.allowedTools.contains(tool), equals(expected));
        });
      }
    }
  });

  group('every role is covered by the tools specification', () {
    for (final role in StepRole.values) {
      test(role.name, () {
        expect(_allowedToolsByRole.containsKey(role), isTrue);
      });
    }
  });

  group('no role may use more than the read-only tools', () {
    for (final role in StepRole.values) {
      test(role.name, () {
        expect(readOnlyTools.containsAll(role.allowedTools), isTrue);
      });
    }
  });

  group('ClaudeTool.wire', () {
    const expectedWire = {
      ClaudeTool.read: 'Read',
      ClaudeTool.glob: 'Glob',
      ClaudeTool.grep: 'Grep',
    };
    for (final tool in ClaudeTool.values) {
      test(tool.name, () {
        expect(tool.wire, equals(expectedWire[tool]));
      });
    }
  });

  // The CLI makes its own small helper calls inside every step, on haiku by
  // default. A role that forbids haiku must not see it there either, so the
  // role names the helper model its steps run the CLI with.
  group('StepRole.helperModel', () {
    const helperModelByRole = <StepRole, AgentModel>{
      StepRole.classification: AgentModel.haiku,
      StepRole.fileReading: AgentModel.haiku,
      StepRole.reasoning: AgentModel.sonnet,
      StepRole.implementation: AgentModel.sonnet,
    };
    for (final role in StepRole.values) {
      test('${role.name} -> ${helperModelByRole[role]!.name}', () {
        expect(role.helperModel, helperModelByRole[role]);
      });
      test('${role.name}: the helper model is one the role permits', () {
        expect(role.permits(role.helperModel), isTrue);
      });
    }
  });

  group('ClaudeHelperModelVariable names the CLI settings', () {
    const wireByVariable = <ClaudeHelperModelVariable, String>{
      ClaudeHelperModelVariable.defaultHaikuModel:
          'ANTHROPIC_DEFAULT_HAIKU_MODEL',
      ClaudeHelperModelVariable.smallFastModel: 'ANTHROPIC_SMALL_FAST_MODEL',
    };
    for (final variable in ClaudeHelperModelVariable.values) {
      test(variable.name, () {
        expect(variable.wire, wireByVariable[variable]);
      });
    }
  });
}
