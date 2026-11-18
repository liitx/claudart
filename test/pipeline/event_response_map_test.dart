// event_response_map_test.dart — one row per PipelineEvent subtype asserting
// the AgentResponse it maps to (or null). Mirrors the route_tag matrix style.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agent_response.dart';
import 'package:claudart/pipeline/event_response_map.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:test/test.dart';

void main() {
  const speaker = Speaker.subagent;
  const ws = 'proj';

  group('toResponse — PipelineEvent → AgentResponse', () {
    test('AgentStarted → null (spinner is the active-step pulse)', () {
      const event = AgentStarted(
        stepId:       'reader',
        label:        'Reading',
        model:        AgentModel.haiku,
        displayStep:  1,
        displayTotal: 3,
      );
      expect(toResponse(event, speaker: speaker, workspace: ws), isNull);
    });

    test('AgentCompleted → Result carrying the step id', () {
      final event = AgentCompleted(
        stepId: 'reader',
        usage:  const Usage(input: 50, output: 20, cost: 0.0005, cacheRead: 0),
      );
      final r = toResponse(event, speaker: speaker, workspace: ws);
      expect(r, isA<Result>());
      final result = r! as Result;
      expect(result.subtask, equals('reader'));
      expect(result.workspace, equals(ws));
    });

    test('AgentFailed → Blocker', () {
      const event = AgentFailed(
        stepId: 'plan',
        failureType: FailureType.stepProducedNoResult,
      );
      final r = toResponse(event, speaker: speaker, workspace: ws);
      expect(r, isA<Blocker>());
      expect((r! as Blocker).step, equals('plan'));
    });

    test('AgentFailed with a reason forwards it as errorType', () {
      const event = AgentFailed(
        stepId: 'plan',
        failureType: FailureType.stepExitedNonzero,
        reason: 'claude exited 1: boom',
      );
      final r = toResponse(event, speaker: speaker, workspace: ws);
      expect((r! as Blocker).errorType, equals('claude exited 1: boom'));
    });

    test('AgentFailed with no reason falls back to the generic literal', () {
      const event = AgentFailed(
        stepId: 'plan',
        failureType: FailureType.stepProducedNoResult,
      );
      final r = toResponse(event, speaker: speaker, workspace: ws);
      expect((r! as Blocker).errorType, equals('step failed'));
    });

    test('AgentEscalating → Question carrying the question', () {
      const event = AgentEscalating(
        stepId:         'plan',
        question:       'which file holds the label?',
        unknownContext: 'foo',
      );
      final r = toResponse(event, speaker: speaker, workspace: ws);
      expect(r, isA<Question>());
      final q = r! as Question;
      expect(q.question, equals('which file holds the label?'));
      expect(q.options, isNotEmpty); // unknownContext surfaced
    });

    test('AgentResumed → null', () {
      expect(
        toResponse(const AgentResumed(stepId: 'plan'), speaker: speaker, workspace: ws),
        isNull,
      );
    });

    test('AwaitingApproval → null', () {
      expect(toResponse(const AwaitingApproval(), speaker: speaker, workspace: ws), isNull);
    });

    test('PlanDraft → null (rendered via render.planDraft)', () {
      expect(toResponse(const PlanDraft(plan: 'do x'), speaker: speaker, workspace: ws), isNull);
    });

    test('PipelineCompleted → null', () {
      const ctx = PipelineContext(
        projectRoot: '/tmp/p',
        bug:         'b',
        expected:    'e',
        files:       [],
      );
      expect(toResponse(const PipelineCompleted(ctx: ctx), speaker: speaker, workspace: ws), isNull);
    });
  });
}
