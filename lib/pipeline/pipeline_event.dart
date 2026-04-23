// pipeline_event.dart — typed events emitted by PipelineExecutor
//
// PipelineExecutor implements a stream-based FSM:
//
//   S = {idle, running, escalating, awaitingApproval, complete, failed}
//   C = PipelineEvent subclasses (one per lifecycle transition)
//   δ : S × C → S  — total function, exhaustive switch, self-loop on invalid
//
//   δ(idle,              AgentStarted)     = running
//   δ(running,           AgentCompleted)   = idle          // advance or complete
//   δ(running,           AgentFailed)      = failed
//   δ(running,           AgentEscalating)  = escalating
//   δ(escalating,        AgentResumed)     = running
//   δ(running,           PlanDraft)        = drafting       // flow command only
//   δ(drafting,          AwaitingApproval) = awaitingApproval
//   δ(awaitingApproval,  AgentStarted)     = running        // after user approves
//   δ(*,                 PipelineCompleted) = complete
//
// Invariant: active ∩ {complete, failed} = ∅
// Invariant: PipelineCompleted is always the final event — never re-emitted.
//
// Subscribers:
//   CLI (runFuture) — renders spinners and prompts based on events.
//   zedup UI       — renders Agents Workflow side pane from the same stream.

import 'agent_model.dart';
import 'pipeline_context.dart';
import 'usage.dart';

sealed class PipelineEvent {
  const PipelineEvent();
}

// ── Agent lifecycle ───────────────────────────────────────────────────────────

/// A pipeline step has started executing.
final class AgentStarted extends PipelineEvent {
  final String stepId;
  final String label;
  final AgentModel model;
  final int displayStep;
  final int displayTotal;

  const AgentStarted({
    required this.stepId,
    required this.label,
    required this.model,
    required this.displayStep,
    required this.displayTotal,
  });
}

/// A pipeline step completed successfully.
final class AgentCompleted extends PipelineEvent {
  final String stepId;
  final Usage usage;

  const AgentCompleted({required this.stepId, required this.usage});
}

/// A pipeline step failed (runner returned null).
final class AgentFailed extends PipelineEvent {
  final String stepId;

  const AgentFailed({required this.stepId});
}

// ── Escalation ────────────────────────────────────────────────────────────────

/// A step needs user input to continue — lookup exhausted or direct escalation.
///
/// [unknownContext] is set when a lookup step could not find the answer in
/// scope files — surfaced so the UI can show "Not in files: …" context.
final class AgentEscalating extends PipelineEvent {
  final String question;
  final String? unknownContext;

  const AgentEscalating({required this.question, this.unknownContext});
}

/// User input was received; the pipeline is resuming.
final class AgentResumed extends PipelineEvent {
  const AgentResumed();
}

// ── Flow-command approval gate ────────────────────────────────────────────────

/// The categorization + planning agents have produced a draft plan.
/// Emitted before [AwaitingApproval] so the UI can render the plan text.
final class PlanDraft extends PipelineEvent {
  final String plan;

  const PlanDraft({required this.plan});
}

/// The pipeline is paused at the approval gate — user must confirm before
/// the construct step runs.
final class AwaitingApproval extends PipelineEvent {
  const AwaitingApproval();
}

// ── Terminal ──────────────────────────────────────────────────────────────────

/// The pipeline has finished. Always the final event in the stream.
///
/// [ctx] carries the fully accumulated context — all step outputs and usage.
/// Subscribers that need only the final result should await this event.
final class PipelineCompleted extends PipelineEvent {
  final PipelineContext ctx;

  const PipelineCompleted({required this.ctx});
}
