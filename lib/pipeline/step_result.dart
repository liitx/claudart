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
import 'step_telemetry.dart';
import 'usage.dart';

class StepResult {
  /// The step's final answer text — what gets stored in the context slot
  /// and matched against routes.
  final String text;

  final StepTelemetry telemetry;

  Usage get usage => telemetry.usage;
  String? get thinking => telemetry.thinking;
  String? get stopReason => telemetry.stopReason;
  int? get durationMs => telemetry.durationMs;
  int? get numTurns => telemetry.numTurns;
  List<ModelObservation> get models => telemetry.models;

  StepResult({
    required this.text,
    required Usage usage,
    String? thinking,
    String? stopReason,
    int? durationMs,
    int? numTurns,
    List<ModelObservation> models = const [],
  }) : telemetry = StepTelemetry(
          usage: usage,
          thinking: thinking,
          stopReason: stopReason,
          durationMs: durationMs,
          numTurns: numTurns,
          models: models,
        );
}
