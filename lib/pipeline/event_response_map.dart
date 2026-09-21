// event_response_map.dart — bridges the executor's internal PipelineEvent
// stream to the user-facing AgentResponse blocks the render layer formats.
//
// `runFuture` subscribes to `PipelineExecutor.run()` and renders each returned
// block as the event arrives. Events the spinner already covers (the in-flight
// step) or that carry no user-facing block (resume / approval gate / terminal,
// and PlanDraft which has its own `render.planDraft` path) map to null.

import 'agent_response.dart';
import 'pipeline_event.dart';

/// Maps a single [PipelineEvent] to the [AgentResponse] the render layer should
/// show, or null when the event produces no block of its own.
AgentResponse? toResponse(
  PipelineEvent event, {
  required Speaker speaker,
  required String workspace,
}) {
  switch (event) {
    // The spinner is the active-step pulse — no separate block on start.
    case AgentStarted():
      return null;

    case AgentCompleted(:final stepId, :final usage):
      return Result(
        speaker:      speaker,
        workspace:    workspace,
        subtask:      stepId,
        filesTouched: const [],
        summary:      usage.format(),
      );

    case AgentFailed(:final stepId, :final reason):
      return Blocker(
        speaker:   speaker,
        workspace: workspace,
        step:      stepId,
        errorType: reason ?? 'step failed',
      );

    case AgentEscalating(:final question, :final unknownContext):
      return Question(
        speaker:        speaker,
        origin:         workspace,
        workspace:      workspace,
        blockedSubtask: '',
        question:       question,
        options: (unknownContext == null || unknownContext.isEmpty)
            ? const []
            : ['not in files: $unknownContext'],
      );

    // No block of their own: resume, approval gate, plan draft (rendered via
    // render.planDraft), and the terminal event.
    case AgentResumed():
    case AwaitingApproval():
    case PlanDraft():
    case PipelineCompleted():
      return null;
  }
}
