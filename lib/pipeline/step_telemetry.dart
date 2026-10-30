// step_telemetry.dart — what one model call reported about itself
//
// Held once by StepResult (the runner's return value) and AgentCompleted (the
// event that carries it onward), so the two cannot drift apart on what a call
// records.

import 'model_observation.dart';
import 'usage.dart';

class StepTelemetry {
  const StepTelemetry({
    required this.usage,
    this.thinking,
    this.stopReason,
    this.durationMs,
    this.numTurns,
    this.models = const [],
  });

  final Usage usage;

  /// Extended-thinking content, if the model produced any — captured from
  /// `thinking_delta` stream events, not present in every response (depends
  /// on whether the model chose to reason before answering).
  final String? thinking;

  /// Why the model stopped: `end_turn`, `tool_use`, `max_tokens`, etc.
  final String? stopReason;

  /// Wall-clock duration of the call, from the CLI's own `duration_ms`.
  final int? durationMs;

  /// Number of agentic turns (tool-call round trips) this call took.
  final int? numTurns;

  /// The models this call actually ran on, from the result line's
  /// `modelUsage`. Empty when the CLI did not report any.
  final List<ModelObservation> models;
}
