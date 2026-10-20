// step_roles_test.dart — every step of every flow declares the role it plays,
// and the model it runs on is permitted for that role.
//
// Steps come from AgentFlow.steps, so a new step is covered automatically.
// The role each step is expected to play is a spec below; a step with no entry
// fails, so a new step cannot skip declaring its role. One test per flow per
// step.

import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/step_role.dart';
import 'package:test/test.dart';

/// The role each step of each flow is expected to play, by step id. Written
/// out by hand so the test is a spec, not a copy of the step definitions.
const Map<AgentFlow, Map<String, StepRole>> _expectedRoleByFlowStep = {
  AgentFlow.suggest: {
    'categorize': StepRole.classification,
    'reader': StepRole.fileReading,
    'reasoner': StepRole.reasoning,
    'planner': StepRole.reasoning,
    'lookup': StepRole.reasoning,
    'applier': StepRole.implementation,
  },
  AgentFlow.debug: {
    'categorize': StepRole.classification,
    'reader': StepRole.fileReading,
    'implementer': StepRole.implementation,
  },
  AgentFlow.teardown: {'teardown-analyzer': StepRole.reasoning},
  AgentFlow.flow: {
    'categorize': StepRole.classification,
    'plan': StepRole.reasoning,
    'clarify': StepRole.reasoning,
    'construct': StepRole.implementation,
  },
};

void main() {
  group('every step plays its expected role', () {
    for (final flow in AgentFlow.values) {
      for (final step in flow.steps) {
        test('${flow.name} ${step.id}', () {
          final expected = _expectedRoleByFlowStep[flow]?[step.id];
          expect(
            expected,
            isNotNull,
            reason: '${flow.name} ${step.id} has no expected role in the spec',
          );
          expect(step.role, expected);
        });
      }
    }
  });

  group('every expected role is for a step the flow really has', () {
    _expectedRoleByFlowStep.forEach((flow, rolesByStepId) {
      for (final stepId in rolesByStepId.keys) {
        test('${flow.name} $stepId', () {
          expect(flow.steps.map((step) => step.id), contains(stepId));
        });
      }
    });
  });

  group('every step runs on a model its role permits', () {
    for (final flow in AgentFlow.values) {
      for (final step in flow.steps) {
        test('${flow.name} ${step.id} on ${step.model.name}', () {
          expect(step.role.permits(step.model), isTrue);
        });
      }
    }
  });

  group('haiku only classifies and reads', () {
    for (final flow in AgentFlow.values) {
      for (final step in flow.steps) {
        if (step.model != AgentModel.haiku) continue;
        test('${flow.name} ${step.id}', () {
          expect(
            step.role,
            isIn([StepRole.classification, StepRole.fileReading]),
          );
        });
      }
    }
  });
}
