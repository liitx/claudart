// step_result.dart — typed result of a single ClaudeRunner call
//
// Was an anonymous record ({String text, Usage usage}). Promoted to a class
// for the same reason StepMode replaced a raw bool: this is a domain object
// (a step's result), not a primitive shape — and Dart records require every
// field to be supplied at every construction site with no optional/default
// support, so a record could never grow new fields (thinking, stopReason,
// durationMs, numTurns) without breaking every existing return statement
// anyway. A class with optional named fields grows without breaking anyone
// who doesn't care about the new fields.

import 'model_observation.dart';
import 'usage.dart';

class StepResult {
  /// The step's final answer text — what gets stored in the context slot
  /// and matched against routes.
  final String text;

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

  const StepResult({
    required this.text,
    required this.usage,
    this.thinking,
    this.stopReason,
    this.durationMs,
    this.numTurns,
    this.models = const [],
  });
}
