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

import '../errors/failure_type.dart';
import 'agent_model.dart';
import 'model_observation.dart';
import 'pipeline_context.dart';
import 'step_telemetry.dart';
import 'usage.dart';

/// One value per [PipelineEvent] variant — the closed set a matrix over the
/// events enumerates. Adding a variant to [PipelineEvent] without adding its
/// value here fails to compile, because [PipelineEvent.kind] switches
/// exhaustively with no default arm.
enum PipelineEventKind {
  /// Maps to [AgentStarted].
  agentStarted,

  /// Maps to [AgentCompleted].
  agentCompleted,

  /// Maps to [AgentFailed].
  agentFailed,

  /// Maps to [AgentEscalating].
  agentEscalating,

  /// Maps to [AgentResumed].
  agentResumed,

  /// Maps to [PlanDraft].
  planDraft,

  /// Maps to [AwaitingApproval].
  awaitingApproval,

  /// Maps to [PipelineCompleted].
  pipelineCompleted,
}

/// The logged projection of one [PipelineEvent]: its [kind], the step it
/// belongs to (null for events that belong to no single step), a detail value
/// (the failure reason, the duration in milliseconds, or null), and the
/// [FailureType] (set only for a failed step).
typedef PipelineEventLogRecord = ({
  PipelineEventKind kind,
  String? stepId,
  Object? detail,
  FailureType? failureType,
});

sealed class PipelineEvent {
  const PipelineEvent();

  /// The [PipelineEventKind] of this event. Exhaustive: no wildcard arm.
  PipelineEventKind get kind => switch (this) {
        AgentStarted() => PipelineEventKind.agentStarted,
        AgentCompleted() => PipelineEventKind.agentCompleted,
        AgentFailed() => PipelineEventKind.agentFailed,
        AgentEscalating() => PipelineEventKind.agentEscalating,
        AgentResumed() => PipelineEventKind.agentResumed,
        PlanDraft() => PipelineEventKind.planDraft,
        AwaitingApproval() => PipelineEventKind.awaitingApproval,
        PipelineCompleted() => PipelineEventKind.pipelineCompleted,
      };

  /// The logged projection of this event. Exhaustive: every variant has one,
  /// and a new variant fails to compile until it declares its projection.
  PipelineEventLogRecord get logRecord => switch (this) {
        final AgentStarted event => (
            kind: PipelineEventKind.agentStarted,
            stepId: event.stepId,
            detail: null,
            failureType: null,
          ),
        final AgentCompleted event => (
            kind: PipelineEventKind.agentCompleted,
            stepId: event.stepId,
            detail: event.durationMs,
            failureType: null,
          ),
        final AgentFailed event => (
            kind: PipelineEventKind.agentFailed,
            stepId: event.stepId,
            detail: event.reason,
            failureType: event.failureType,
          ),
        final AgentEscalating event => (
            kind: PipelineEventKind.agentEscalating,
            stepId: event.stepId,
            detail: event.question,
            failureType: null,
          ),
        final AgentResumed event => (
            kind: PipelineEventKind.agentResumed,
            stepId: event.stepId,
            detail: null,
            failureType: null,
          ),
        PlanDraft() => (
            kind: PipelineEventKind.planDraft,
            stepId: null,
            detail: null,
            failureType: null,
          ),
        AwaitingApproval() => (
            kind: PipelineEventKind.awaitingApproval,
            stepId: null,
            detail: null,
            failureType: null,
          ),
        PipelineCompleted() => (
            kind: PipelineEventKind.pipelineCompleted,
            stepId: null,
            detail: null,
            failureType: null,
          ),
      };
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
  final StepTelemetry telemetry;

  Usage get usage => telemetry.usage;

  /// True when the step's `postProcess` changed its output. `run()` never
  /// writes to stdout itself (see this file's own header contract) — this
  /// flag is how a caller that wants a trace line (e.g. `runFuture`'s
  /// `verbose` option) knows to print one, without the executor doing IO
  /// directly inside the generator.
  final bool postProcessRewrote;

  /// Thinking content is per-step only — never accumulated onto
  /// [PipelineContext.usage], unlike [Usage.thinkingTokens] which is a real
  /// additive count.
  String? get thinking => telemetry.thinking;
  String? get stopReason => telemetry.stopReason;
  int? get durationMs => telemetry.durationMs;
  int? get numTurns => telemetry.numTurns;
  /// The model the step intended, and the models it actually ran on (from the
  /// stream). Together they are the per-step model record.
  /// Null only for events built by a consumer that does not know it.
  final AgentModel? intendedModel;
  List<ModelObservation> get models => telemetry.models;

  AgentCompleted({
    required this.stepId,
    required Usage usage,
    this.intendedModel,
    List<ModelObservation> models = const [],
    this.postProcessRewrote = false,
    String? thinking,
    String? stopReason,
    int? durationMs,
    int? numTurns,
  }) : telemetry = StepTelemetry(
          usage: usage,
          thinking: thinking,
          stopReason: stopReason,
          durationMs: durationMs,
          numTurns: numTurns,
          models: models,
        );
}

/// A pipeline step failed (runner returned null).
///
/// [reason] is the runner's own diagnostic message when available (exit
/// code + stderr, a missing/empty result line, a caught exception) — null
/// only when a test-injected runner returns null with no reason to give.
final class AgentFailed extends PipelineEvent {
  final String stepId;
  final String? reason;

  /// Which failure this was. A typed exception keeps its own type; anything
  /// else is [FailureType.unexpectedFailure], a marker that a type is missing.
  final FailureType failureType;

  const AgentFailed({
    required this.stepId,
    required this.failureType,
    this.reason,
  });
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
