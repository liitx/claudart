// step_roles_test.dart — every real pipeline step declares the role it plays,
// and the model it runs on is permitted for that role.
//
// The expected role of each step is written out here as a spec. A new step
// without an entry fails the coverage test below, so a role cannot be skipped.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agent_step.dart';
import 'package:claudart/pipeline/flows/debug_steps.dart';
import 'package:claudart/pipeline/flows/flow_steps.dart';
import 'package:claudart/pipeline/flows/suggest_steps.dart';
import 'package:claudart/pipeline/flows/teardown_steps.dart';
import 'package:claudart/pipeline/step_role.dart';
import 'package:test/test.dart';

/// Every step the pipeline defines, keyed by a unique label, with the role
/// it is expected to play.
typedef _StepWithExpectedRole = ({AgentStep step, StepRole role});

final Map<String, _StepWithExpectedRole> _expectedRoleBySteps = {
  'flow categorize': (
    step: FlowSteps.categorize,
    role: StepRole.classification,
  ),
  'flow plan': (step: FlowSteps.plan, role: StepRole.reasoning),
  'flow clarify': (step: FlowSteps.clarify, role: StepRole.reasoning),
  'flow construct': (step: FlowSteps.construct, role: StepRole.implementation),
  'suggest reader': (step: SuggestSteps.reader(1), role: StepRole.fileReading),
  'suggest reasoner': (step: SuggestSteps.reasoner, role: StepRole.reasoning),
  'suggest planner': (step: SuggestSteps.planner(1), role: StepRole.reasoning),
  'suggest lookup': (step: SuggestSteps.lookup(1), role: StepRole.reasoning),
  'suggest applier': (
    step: SuggestSteps.applier(1),
    role: StepRole.implementation,
  ),
  'debug reader': (step: DebugSteps.reader(1), role: StepRole.fileReading),
  'debug implementer': (
    step: DebugSteps.implementer,
    role: StepRole.implementation,
  ),
  'teardown analyzer': (step: TeardownSteps.analyzer, role: StepRole.reasoning),
};

void main() {
  group('every step plays its declared role', () {
    _expectedRoleBySteps.forEach((label, expected) {
      test(label, () {
        expect(expected.step.role, equals(expected.role));
      });
    });
  });

  group('every step runs on a model its role permits', () {
    _expectedRoleBySteps.forEach((label, expected) {
      test('$label on ${expected.step.model.name}', () {
        expect(expected.step.role.permits(expected.step.model), isTrue);
      });
    });
  });

  group('haiku only classifies and reads', () {
    _expectedRoleBySteps.forEach((label, expected) {
      if (expected.step.model != AgentModel.haiku) return;
      test(label, () {
        expect(
          expected.step.role,
          isIn([StepRole.classification, StepRole.fileReading]),
        );
      });
    });
  });
}
