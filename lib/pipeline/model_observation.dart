// model_observation.dart — the model a step actually ran on, as the `claude`
// stream reported it, set against what claudart declared for it.
//
// Three kinds of model information (docs/design.md 9.6):
//   declared  AgentModel in code, keyed by alias
//   resolved  the machine's alias mapping, re-read at launch (a prediction)
//   observed  this file: the final `result` line's `modelUsage`, per step
//
// The observation costs nothing extra: it is read from a line claudart already
// receives and parses, so it adds no model call and no prompt tokens.

import 'agent_model.dart';

/// One model's usage within a step, as `modelUsage[<id>]` reports it.
class ModelObservation {
  const ModelObservation({
    required this.observedModelId,
    this.canonicalModel,
    this.provider,
    this.observedContextWindow,
    this.observedMaxOutputTokens,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.thinkingTokens = 0,
    this.costUsd = 0,
  });

  /// The id the API answered with, e.g. `claude-haiku-4-5-20251001`.
  final String observedModelId;
  final String? canonicalModel;
  final String? provider;
  final int? observedContextWindow;
  final int? observedMaxOutputTokens;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int thinkingTokens;
  final double costUsd;

  /// Tokens that occupied the context window for this model in the step.
  int get contextTokens => inputTokens + cacheReadTokens + cacheCreationTokens;

  Map<String, Object?> toJson() => {
        ModelObservationField.observedModelId.jsonKey: observedModelId,
        ModelObservationField.canonicalModel.jsonKey: canonicalModel,
        ModelObservationField.provider.jsonKey: provider,
        ModelObservationField.contextWindow.jsonKey: observedContextWindow,
        ModelObservationField.maxOutputTokens.jsonKey:
            observedMaxOutputTokens,
        ModelObservationField.inputTokens.jsonKey: inputTokens,
        ModelObservationField.outputTokens.jsonKey: outputTokens,
        ModelObservationField.cacheReadTokens.jsonKey: cacheReadTokens,
        ModelObservationField.cacheCreationTokens.jsonKey:
            cacheCreationTokens,
        ModelObservationField.thinkingTokens.jsonKey: thinkingTokens,
        ModelObservationField.costUsd.jsonKey: costUsd,
      };
}

/// The fields of a [ModelObservation]. The variant's own name is its key in
/// the persisted record; [streamKey] is the key in the stream's
/// `modelUsage[<id>]` object where that differs from the name.
enum ModelObservationField {
  /// The id is the map key itself, not a field of the object.
  observedModelId(hasStreamKey: false),
  canonicalModel,
  provider,
  contextWindow,
  maxOutputTokens,
  inputTokens,
  outputTokens,
  cacheReadTokens(streamKey: 'cacheReadInputTokens'),
  cacheCreationTokens(streamKey: 'cacheCreationInputTokens'),
  thinkingTokens,
  costUsd(streamKey: 'costUSD');

  const ModelObservationField({this.streamKey, this.hasStreamKey = true});

  final String? streamKey;
  final bool hasStreamKey;

  /// The key in the persisted record.
  String get jsonKey => name;

  /// The key in `modelUsage[<id>]`, or null for the id.
  String? get wireStreamKey => hasStreamKey ? (streamKey ?? name) : null;
}

/// Every model in a result line's `modelUsage`, in the order reported. Empty
/// when the line has none (older CLI, error result) — never throws, since this
/// is enrichment and must not fail a step.
List<ModelObservation> parseModelUsage(Object? modelUsage) {
  if (modelUsage is! Map<String, dynamic>) return const [];
  return [
    for (final entry in modelUsage.entries)
      if (entry.value is Map<String, dynamic>)
        _observationOf(entry.key, entry.value as Map<String, dynamic>),
  ];
}

ModelObservation _observationOf(String id, Map<String, dynamic> usage) {
  int? intOf(ModelObservationField field) {
    final value = usage[field.wireStreamKey];
    return value is num ? value.toInt() : null;
  }

  String? textOf(ModelObservationField field) {
    final value = usage[field.wireStreamKey];
    return value is String ? value : null;
  }

  return ModelObservation(
    observedModelId: id,
    canonicalModel: textOf(ModelObservationField.canonicalModel),
    provider: textOf(ModelObservationField.provider),
    observedContextWindow: intOf(ModelObservationField.contextWindow),
    observedMaxOutputTokens: intOf(ModelObservationField.maxOutputTokens),
    inputTokens: intOf(ModelObservationField.inputTokens) ?? 0,
    outputTokens: intOf(ModelObservationField.outputTokens) ?? 0,
    cacheReadTokens: intOf(ModelObservationField.cacheReadTokens) ?? 0,
    cacheCreationTokens: intOf(ModelObservationField.cacheCreationTokens) ?? 0,
    thinkingTokens: intOf(ModelObservationField.thinkingTokens) ?? 0,
    costUsd: (usage[ModelObservationField.costUsd.wireStreamKey] as num?)
            ?.toDouble() ??
        0,
  );
}

/// How an observation disagrees with what claudart declared.
enum ModelDriftKind {
  /// The observed id is not any [AgentModel.slug].
  unknownModel,

  /// A known model, but not the one the step intended.
  differsFromIntended,

  /// Observed context window differs from [AgentModel.contextWindow].
  contextWindow,

  /// Observed output cap differs from [AgentModel.maxOutputTokens].
  maxOutputTokens;
}

/// One observation set against the model the step intended.
class ModelReconciliation {
  const ModelReconciliation({
    required this.intended,
    required this.observation,
    required this.resolved,
    required this.drift,
    required this.contextUsedFraction,
    required this.outputCapReached,
  });

  final AgentModel intended;
  final ModelObservation observation;

  /// The [AgentModel] whose slug is the observed id, null when none is.
  final AgentModel? resolved;
  final Set<ModelDriftKind> drift;

  /// [ModelObservation.contextTokens] over the context window (the observed
  /// one when reported, else the resolved model's declared one); null when
  /// neither is known.
  final double? contextUsedFraction;

  /// The step produced as many tokens as the output cap allows.
  final bool outputCapReached;

  /// The persisted per-step record (keys are [ModelRecordField] names).
  Map<String, Object?> toRecordJson({required String stepId}) => {
        ModelRecordField.stepId.name: stepId,
        ModelRecordField.intended.name: intended.alias,
        ModelRecordField.resolved.name: resolved?.alias,
        ModelRecordField.drift.name: [for (final kind in drift) kind.name],
        ModelRecordField.contextUsedFraction.name: contextUsedFraction,
        ModelRecordField.outputCapReached.name: outputCapReached,
        ModelRecordField.observation.name: observation.toJson(),
      };
}

/// A persisted per-step record (see [ModelReconciliation.toRecordJson]) as one
/// line for a person: step, intended -> observed id, context used, drift.
String describeModelRecord(Map<String, dynamic> record) {
  final observation =
      record[ModelRecordField.observation.name] as Map<String, dynamic>? ?? {};
  final fraction = record[ModelRecordField.contextUsedFraction.name] as num?;
  final drift = (record[ModelRecordField.drift.name] as List?)?.cast<String>() ??
      const <String>[];
  final observedId =
      observation[ModelObservationField.observedModelId.jsonKey];
  final context = fraction == null ? '-' : '${(fraction * 100).round()}%';
  return '${record[ModelRecordField.stepId.name]}  '
      '${record[ModelRecordField.intended.name]} -> $observedId  '
      'context $context  '
      'drift: ${drift.isEmpty ? 'none' : drift.join(', ')}';
}

/// The keys of one persisted per-step model record, written by their own
/// names; the enum is the list of what a record holds.
enum ModelRecordField {
  stepId,
  intended,
  resolved,
  drift,
  contextUsedFraction,
  outputCapReached,
  observation;
}

/// Compares [observation] with [intended] and with the declared facts of the
/// model it resolves to.
ModelReconciliation reconcileModel({
  required AgentModel intended,
  required ModelObservation observation,
}) {
  final resolved = AgentModel.fromSlug(observation.observedModelId);
  final window = observation.observedContextWindow ?? resolved?.contextWindow;
  final cap = observation.observedMaxOutputTokens ?? resolved?.maxOutputTokens;
  return ModelReconciliation(
    intended: intended,
    observation: observation,
    resolved: resolved,
    drift: {
      if (resolved == null) ModelDriftKind.unknownModel,
      if (resolved != null && resolved != intended)
        ModelDriftKind.differsFromIntended,
      if (resolved != null &&
          observation.observedContextWindow != null &&
          observation.observedContextWindow != resolved.contextWindow)
        ModelDriftKind.contextWindow,
      if (resolved != null &&
          observation.observedMaxOutputTokens != null &&
          observation.observedMaxOutputTokens != resolved.maxOutputTokens)
        ModelDriftKind.maxOutputTokens,
    },
    contextUsedFraction:
        window == null || window == 0 ? null : observation.contextTokens / window,
    outputCapReached: cap != null && observation.outputTokens >= cap,
  );
}
