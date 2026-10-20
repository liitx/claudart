// step_role_test.dart — which models each pipeline step role may run on.
//
// Haiku is the cheapest model and is not sufficient to reason or implement.
// It may only classify and read; reasoning and implementation run on sonnet
// or opus. One test per (role, model) cell, so a changed permission fails by
// name.

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
}
