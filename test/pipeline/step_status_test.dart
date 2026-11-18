// step_status_test.dart — StepStatusFromEvent.fromEvent, the canonical
// PipelineEvent → StepStatus projection. One test() per PipelineEvent
// subtype, per dartrix's testing paradigm — a loop here would collapse
// every variant's pass/fail into one result and hide failures after the
// first.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/state_hue.dart';
import 'package:claudart/pipeline/step_status.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:test/test.dart';

void main() {
  group('StepStatusFromEvent.fromEvent', () {
    test('AgentStarted maps to running', () {
      const event = AgentStarted(
        stepId: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        displayStep: 1,
        displayTotal: 1,
      );
      expect(StepStatusFromEvent.fromEvent(event), equals(StepStatus.running));
    });

    test('AgentCompleted maps to done', () {
      final event = AgentCompleted(stepId: 'a', usage: const Usage());
      expect(StepStatusFromEvent.fromEvent(event), equals(StepStatus.done));
    });

    test('AgentFailed maps to failed', () {
      const event = AgentFailed(
        stepId: 'a',
        failureType: FailureType.stepProducedNoResult,
      );
      expect(StepStatusFromEvent.fromEvent(event), equals(StepStatus.failed));
    });

    test('AgentEscalating maps to waiting', () {
      const event = AgentEscalating(stepId: 'a', question: 'which file?');
      expect(StepStatusFromEvent.fromEvent(event), equals(StepStatus.waiting));
    });

    test('AgentResumed maps to running', () {
      const event = AgentResumed(stepId: 'a');
      expect(StepStatusFromEvent.fromEvent(event), equals(StepStatus.running));
    });

    test('PlanDraft carries no per-step status change', () {
      const event = PlanDraft(plan: 'draft text');
      expect(StepStatusFromEvent.fromEvent(event), isNull);
    });

    test('AwaitingApproval carries no per-step status change', () {
      const event = AwaitingApproval();
      expect(StepStatusFromEvent.fromEvent(event), isNull);
    });

    test('PipelineCompleted carries no per-step status change', () {
      const event = PipelineCompleted(
        ctx: PipelineContext(projectRoot: '/tmp', bug: '', expected: '', files: []),
      );
      expect(StepStatusFromEvent.fromEvent(event), isNull);
    });
  });

  group('StepStatus.hue', () {
    const expected = {
      StepStatus.pending: StateHue.inactive,
      StepStatus.running: StateHue.active,
      StepStatus.waiting: StateHue.paused,
      StepStatus.done: StateHue.success,
      StepStatus.failed: StateHue.error,
    };

    for (final status in StepStatus.values) {
      test(status.name, () {
        expect(status.hue, equals(expected[status]));
      });
    }
  });

  group('StepStatus.glyph', () {
    const expected = {
      StepStatus.pending: '○',
      StepStatus.running: '◉',
      StepStatus.waiting: '◉',
      StepStatus.done: '✓',
      StepStatus.failed: '✗',
    };

    for (final status in StepStatus.values) {
      test(status.name, () {
        expect(status.glyph, equals(expected[status]));
      });
    }
  });
}
