import 'dart:convert';
import 'dart:io';

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/model_observation.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:test/test.dart';

// The real result line a `claude -p --output-format stream-json --verbose`
// haiku run produced (ids redacted): test/fixtures/claude_result_line_haiku.json
final _realResultLine =
    File('test/fixtures/claude_result_line_haiku.json').readAsStringSync().trim();

const _haikuId = 'claude-haiku-4-5-20251001';

void main() {
  group('parseModelUsage on the real captured line', () {
    final observed = parseModelUsage(
      (jsonDecode(_realResultLine) as Map<String, dynamic>)['modelUsage'],
    ).single;

    test('names the model the API answered with', () {
      expect(observed.observedModelId, _haikuId);
      expect(observed.canonicalModel, 'claude-haiku-4-5');
      expect(observed.provider, 'firstParty');
    });

    test('carries the window, the output cap and the per-model counts', () {
      expect(observed.observedContextWindow, 200000);
      expect(observed.observedMaxOutputTokens, 32000);
      expect(observed.inputTokens, 908);
      expect(observed.outputTokens, 52);
      expect(observed.cacheReadTokens, 13978);
      expect(observed.cacheCreationTokens, 8429);
      expect(observed.thinkingTokens, 34);
      expect(observed.costUsd, 0.0194238);
    });

    test('the step result carries it, from the same line', () {
      final result = parseClaudeResultLine(
        _realResultLine,
        thinkingBuffer: null,
        thinkingTokens: 0,
      );
      expect(result.models.single.observedModelId, _haikuId);
      expect(result.text, 'ok');
    });
  });

  group('parseModelUsage tolerates what it cannot read', () {
    final cases = <String, Object?>{
      'missing': null,
      'a list': [1],
      'a scalar': 'x',
      'a model with no object': {'claude-x': 'oops'},
    };
    cases.forEach((name, value) {
      test('$name gives no observations and does not throw', () {
        expect(parseModelUsage(value), isEmpty);
      });
    });

    test('keeps every model reported, in order', () {
      final models = parseModelUsage({
        'a': {'inputTokens': 1},
        'b': {'inputTokens': 2},
      });
      expect(models.map((m) => m.observedModelId), ['a', 'b']);
      expect(models.map((m) => m.inputTokens), [1, 2]);
    });
  });

  group('ModelObservationField', () {
    test('jsonKey values are unique, so a record cannot lose a field', () {
      final keys = ModelObservationField.values.map((f) => f.jsonKey);
      expect(keys.toSet().length, ModelObservationField.values.length);
    });

    test('toJson has exactly one entry per field', () {
      const observation = ModelObservation(observedModelId: 'x');
      expect(
        observation.toJson().keys.toSet(),
        {for (final f in ModelObservationField.values) f.jsonKey},
      );
    });
  });

  group('ModelObservation.contextTokens', () {
    test('is input plus cache read plus cache creation', () {
      const observation = ModelObservation(
        observedModelId: 'x',
        inputTokens: 1000,
        cacheReadTokens: 20,
        cacheCreationTokens: 3,
      );
      expect(observation.contextTokens, 1023);
    });
  });

  group('reconcileModel', () {
    ModelObservation observed({
      String id = _haikuId,
      int? window = 200000,
      int? cap = 8192,
      int input = 100,
      int output = 10,
    }) =>
        ModelObservation(
          observedModelId: id,
          observedContextWindow: window,
          observedMaxOutputTokens: cap,
          inputTokens: input,
          outputTokens: output,
        );

    test('a model that matches its declaration has no drift', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(),
      );
      expect(r.drift, isEmpty);
      expect(r.resolved, AgentModel.haiku);
    });

    test('the real capture drifts on max output tokens: 32000 vs declared', () {
      final real = parseModelUsage(
        (jsonDecode(_realResultLine) as Map<String, dynamic>)['modelUsage'],
      ).single;
      final r = reconcileModel(intended: AgentModel.haiku, observation: real);
      expect(r.drift, {ModelDriftKind.maxOutputTokens});
    });

    test('an id that is no AgentModel slug is unknownModel', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(id: 'claude-future-9'),
      );
      expect(r.drift, {ModelDriftKind.unknownModel});
      expect(r.resolved, isNull);
    });

    test('a different known model than intended is flagged', () {
      final r = reconcileModel(
        intended: AgentModel.sonnet,
        observation: observed(),
      );
      expect(r.drift, {ModelDriftKind.differsFromIntended});
    });

    test('a different context window is flagged', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(window: 1000000),
      );
      expect(r.drift, {ModelDriftKind.contextWindow});
    });

    test('context used is tokens in context over the window', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(input: 50000, window: 200000),
      );
      expect(r.contextUsedFraction, 0.25);
    });

    test('with no observed window it falls back to the declared one', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(input: 100000, window: null),
      );
      expect(r.contextUsedFraction, 0.5);
    });

    test('with no window anywhere the fraction is unknown', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(id: 'claude-future-9', window: null),
      );
      expect(r.contextUsedFraction, isNull);
    });

    test('output above the cap is reported too', () {
      final r = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(cap: 100, output: 101),
      );
      expect(r.outputCapReached, isTrue);
    });

    test('output at the cap is reported; below it is not', () {
      final at = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(cap: 100, output: 100),
      );
      final below = reconcileModel(
        intended: AgentModel.haiku,
        observation: observed(cap: 100, output: 99),
      );
      expect(at.outputCapReached, isTrue);
      expect(below.outputCapReached, isFalse);
    });
  });

  group('describeModelRecord', () {
    Map<String, dynamic> record({
      Object? fraction = 0.256,
      List<String> drift = const [],
    }) =>
        {
          ModelRecordField.stepId.name: 'reader',
          ModelRecordField.intended.name: 'haiku',
          ModelRecordField.contextUsedFraction.name: fraction,
          ModelRecordField.drift.name: drift,
          ModelRecordField.observation.name: {
            ModelObservationField.observedModelId.jsonKey: _haikuId,
          },
        };

    test('reads step, intended -> observed, rounded context, no drift', () {
      expect(
        describeModelRecord(record()),
        'reader  haiku -> $_haikuId  context 26%  drift: none',
      );
    });

    test('lists every drift kind', () {
      expect(
        describeModelRecord(record(drift: ['contextWindow', 'maxOutputTokens'])),
        endsWith('drift: contextWindow, maxOutputTokens'),
      );
    });

    test('an unknown context fraction shows a dash', () {
      expect(describeModelRecord(record(fraction: null)), contains('context -'));
    });
  });

  group('ModelReconciliation.toRecordJson', () {
    test('carries the step id, intended alias and the drift names', () {
      final json = reconcileModel(
        intended: AgentModel.sonnet,
        observation: const ModelObservation(observedModelId: _haikuId),
      ).toRecordJson(stepId: 'planner');
      expect(json[ModelRecordField.stepId.name], 'planner');
      expect(json[ModelRecordField.intended.name], 'sonnet');
      expect(json[ModelRecordField.resolved.name], 'haiku');
      expect(json[ModelRecordField.drift.name], ['differsFromIntended']);
    });
  });

  group('ModelObservationField keys', () {
    // (persisted key, key in the stream's modelUsage object or null for the id)
    const keys = <ModelObservationField, (String, String?)>{
      ModelObservationField.observedModelId: ('observedModelId', null),
      ModelObservationField.canonicalModel: ('canonicalModel', 'canonicalModel'),
      ModelObservationField.provider: ('provider', 'provider'),
      ModelObservationField.contextWindow: ('contextWindow', 'contextWindow'),
      ModelObservationField.maxOutputTokens:
          ('maxOutputTokens', 'maxOutputTokens'),
      ModelObservationField.inputTokens: ('inputTokens', 'inputTokens'),
      ModelObservationField.outputTokens: ('outputTokens', 'outputTokens'),
      ModelObservationField.cacheReadTokens:
          ('cacheReadTokens', 'cacheReadInputTokens'),
      ModelObservationField.cacheCreationTokens:
          ('cacheCreationTokens', 'cacheCreationInputTokens'),
      ModelObservationField.thinkingTokens:
          ('thinkingTokens', 'thinkingTokens'),
      ModelObservationField.costUsd: ('costUsd', 'costUSD'),
    };

    for (final field in ModelObservationField.values) {
      test('${field.name}: persisted and stream keys', () {
        expect((field.jsonKey, field.wireStreamKey), keys[field]);
      });
    }

    test('every variant has a pinned key', () {
      expect(keys.keys.toSet(), ModelObservationField.values.toSet());
    });
  });
}
