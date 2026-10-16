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
import 'model_observation.dart';
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

  /// True when [stepId] has already run earlier in this same pipeline run —
  /// the executor's routing graph looped back to it (e.g. `flow`'s clarify
  /// step's `FeedBackTo`/`EscalateUser` routes returning to `plan`). A
  /// subscriber rendering the step sequence as a graph uses this to draw a
  /// cycle rather than assuming every step is a straight-line advance.
  final bool isRevisit;

  const AgentStarted({
    required this.stepId,
    required this.label,
    required this.model,
    required this.displayStep,
    required this.displayTotal,
    this.isRevisit = false,
  });
}

/// A pipeline step completed successfully.
final class AgentCompleted extends PipelineEvent {
  final String stepId;
  final Usage usage;

  /// True when the step's `postProcess` changed its output. `run()` never
  /// writes to stdout itself (see this file's own header contract) — this
  /// flag is how a caller that wants a trace line (e.g. `runFuture`'s
  /// `verbose` option) knows to print one, without the executor doing IO
  /// directly inside the generator.
  final bool postProcessRewrote;

  /// Extended-thinking content the model produced before answering, if any.
  /// Per-step only — never accumulated onto [PipelineContext.usage], unlike
  /// [Usage.thinkingTokens] which is a real additive count.
  final String? thinking;

  /// Why the model stopped: `end_turn`, `tool_use`, `max_tokens`, etc.
  final String? stopReason;

  /// Wall-clock duration of this step's call, in milliseconds.
  final int? durationMs;

  /// Number of agentic turns (tool-call round trips) this step's call took.
  final int? numTurns;

  /// The model the step intended, and the models it actually ran on (from the
  /// stream). Together they are the per-step model record.
  /// Null only for events built by a consumer that does not know it.
  final AgentModel? intendedModel;
  final List<ModelObservation> models;

  const AgentCompleted({
    required this.stepId,
    required this.usage,
    this.intendedModel,
    this.models = const [],
    this.postProcessRewrote = false,
    this.thinking,
    this.stopReason,
    this.durationMs,
    this.numTurns,
  });
}

/// A pipeline step failed (runner returned null).
///
/// [reason] is the runner's own diagnostic message when available (exit
/// code + stderr, a missing/empty result line, a caught exception) — null
/// only when a test-injected runner returns null with no reason to give.
final class AgentFailed extends PipelineEvent {
  final String stepId;
  final String? reason;

  const AgentFailed({required this.stepId, this.reason});
}

// ── Escalation ────────────────────────────────────────────────────────────────

/// A step needs user input to continue — lookup exhausted or direct escalation.
///
/// [unknownContext] is set when a lookup step could not find the answer in
/// scope files — surfaced so the UI can show "Not in files: …" context.
final class AgentEscalating extends PipelineEvent {
  final String stepId;
  final String question;
  final String? unknownContext;

  const AgentEscalating({
    required this.stepId,
    required this.question,
    this.unknownContext,
  });
}

/// User input was received; the pipeline is resuming.
final class AgentResumed extends PipelineEvent {
  final String stepId;

  const AgentResumed({required this.stepId});
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
