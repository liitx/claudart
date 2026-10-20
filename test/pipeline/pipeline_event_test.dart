// pipeline_event_test.dart — every PipelineEvent variant has a kind and a
// logged projection.
//
// Each variant is built here and compared with the kind and the record it is
// expected to log, written out by hand so the test is a spec. A kind with no
// case here fails the closed-world test, so a new variant cannot skip being
// specified.

import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:test/test.dart';
import '../helpers/project_fixture.dart';

typedef _EventCase = ({PipelineEvent event, PipelineEventLogRecord record});

final Map<PipelineEventKind, _EventCase> _casesByKind = {
  PipelineEventKind.agentStarted: (
    event: const AgentStarted(
      stepId: 'reader',
      label: 'Reading',
      model: AgentModel.haiku,
      displayStep: 2,
      displayTotal: 4,
    ),
    record: (
      kind: PipelineEventKind.agentStarted,
      stepId: 'reader',
      detail: null,
      failureType: null,
    ),
  ),
  PipelineEventKind.agentCompleted: (
    event: const AgentCompleted(
      stepId: 'reasoner',
      usage: Usage(),
      durationMs: 1234,
    ),
    record: (
      kind: PipelineEventKind.agentCompleted,
      stepId: 'reasoner',
      detail: 1234,
      failureType: null,
    ),
  ),
  PipelineEventKind.agentFailed: (
    event: const AgentFailed(
      stepId: 'implementer',
      reason: 'timed out',
      failureType: FailureType.stepTimedOut,
    ),
    record: (
      kind: PipelineEventKind.agentFailed,
      stepId: 'implementer',
      detail: 'timed out',
      failureType: FailureType.stepTimedOut,
    ),
  ),
  PipelineEventKind.agentEscalating: (
    event: const AgentEscalating(stepId: 'lookup', question: 'which file?'),
    record: (
      kind: PipelineEventKind.agentEscalating,
      stepId: 'lookup',
      detail: 'which file?',
      failureType: null,
    ),
  ),
  PipelineEventKind.agentResumed: (
    event: const AgentResumed(stepId: 'lookup'),
    record: (
      kind: PipelineEventKind.agentResumed,
      stepId: 'lookup',
      detail: null,
      failureType: null,
    ),
  ),
  PipelineEventKind.planDraft: (
    event: const PlanDraft(plan: 'the plan'),
    record: (
      kind: PipelineEventKind.planDraft,
      stepId: null,
      detail: null,
      failureType: null,
    ),
  ),
  PipelineEventKind.awaitingApproval: (
    event: const AwaitingApproval(),
    record: (
      kind: PipelineEventKind.awaitingApproval,
      stepId: null,
      detail: null,
      failureType: null,
    ),
  ),
  PipelineEventKind.pipelineCompleted: (
    event: const PipelineCompleted(
      ctx: PipelineContext(
        projectRoot: ProjectFixture.root,
        bug: '',
        expected: '',
        files: [],
      ),
    ),
    record: (
      kind: PipelineEventKind.pipelineCompleted,
      stepId: null,
      detail: null,
      failureType: null,
    ),
  ),
};

void main() {
  test('every PipelineEventKind has a case in this spec', () {
    expect(_casesByKind.keys.toSet(), PipelineEventKind.values.toSet());
  });

  group('PipelineEvent.kind', () {
    _casesByKind.forEach((kind, eventCase) {
      test(kind.name, () {
        expect(eventCase.event.kind, kind);
      });
    });
  });

  group('PipelineEvent.logRecord', () {
    _casesByKind.forEach((kind, eventCase) {
      test(kind.name, () {
        expect(eventCase.event.logRecord, eventCase.record);
      });
    });

    test('a completed step with no duration logs a null detail', () {
      expect(
        const AgentCompleted(stepId: 'reader', usage: Usage())
            .logRecord
            .detail,
        isNull,
      );
    });

    test('a failed step with no reason logs a null detail', () {
      expect(
        const AgentFailed(
          stepId: 'reader',
          failureType: FailureType.stepProducedNoResult,
        ).logRecord.detail,
        isNull,
      );
    });
  });
}
