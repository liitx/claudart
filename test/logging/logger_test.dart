import 'dart:convert';
import 'package:test/test.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/model_observation.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/sensitivity/token_map.dart';
import 'package:path/path.dart' as p;
import '../helpers/mocks.dart';
import 'package:claudart/paths.dart';

String get _logsDir => p.join(claudeDir, 'logs');
String get _interactionsPath => p.join(_logsDir, 'interactions.jsonl');
String get _errorsPath => p.join(_logsDir, 'errors.jsonl');
String get _transitionsPath => p.join(_logsDir, 'transitions.jsonl');
String get _performancePath => p.join(_logsDir, 'performance.md');
String get _modelsPath => p.join(_logsDir, 'models.jsonl');

void main() {
  group('SessionLogger', () {
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger(io: io);
    });

    List<Map<String, dynamic>> readJsonl(String path) {
      final raw = io.read(path);
      if (raw.isEmpty) return [];
      return raw
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
    }

    test('logInteraction appends one jsonl line', () {
      logger.logInteraction(command: 'setup', outcome: 'ok');
      final entries = readJsonl(_interactionsPath);
      expect(entries, hasLength(1));
      expect(entries.first['command'], equals('setup'));
      expect(entries.first['outcome'], equals('ok'));
    });

    test('logInteraction stores all optional fields', () {
      logger.logInteraction(
        command: 'scan',
        outcome: 'ok',
        scanScope: 'lib',
        filesScanned: 42,
        tokensTotal: 10,
        tokensNew: 3,
        scanDuration: 1.5,
        platform: 'darwin',
        claudartVersion: '1.0.0',
      );
      final entry = readJsonl(_interactionsPath).first;
      expect(entry['scanScope'], equals('lib'));
      expect(entry['filesScanned'], equals(42));
      expect(entry['tokensNew'], equals(3));
    });

    test('logTransition records the command and the typed transition', () {
      logger.logTransition(
        command: 'suggest',
        transition: const HandoffTransition(
          from: HandoffStatus.suggestInvestigating,
          event: HandoffEvent.saveConfirmedReady,
          to: HandoffStatus.readyForDebug,
        ),
      );
      final entries = readJsonl(_transitionsPath);
      expect(entries, hasLength(1));
      expect(entries.first['ts'], isA<String>());
      expect({...entries.first}..remove('ts'), {
        'command': 'suggest',
        'from': 'suggestInvestigating',
        'event': 'saveConfirmedReady',
        'to': 'readyForDebug',
      });
    });

    test('logHandoffMove logs an allowed move exactly like logTransition', () {
      logger.logHandoffMove(
        command: 'kill',
        from: HandoffStatus.readyForDebug,
        event: HandoffEvent.killed,
      );
      expect(readJsonl(_transitionsPath).map((e) => {...e}..remove('ts')), [
        {
          'command': 'kill',
          'from': 'readyForDebug',
          'event': 'killed',
          'to': 'noHandoff',
        },
      ]);
    });

    test('logHandoffMove marks a move the table lacks as rejected, no to', () {
      logger.logHandoffMove(
        command: 'rotate',
        from: HandoffStatus.debugComplete,
        event: HandoffEvent.rotated,
      );
      expect(readJsonl(_transitionsPath).map((e) => {...e}..remove('ts')), [
        {
          'command': 'rotate',
          'from': 'debugComplete',
          'event': 'rotated',
          'rejected': true,
        },
      ]);
    });

    test('logError appends with fingerprint', () {
      logger.logError(
        command: 'scan',
        errorType: 'threshold_hit',
        fingerprint: 'scan.threshold_hit.generated_files',
        reason: 'generated_files_not_ignored',
        suggestion: 'add *.g.dart to .claudartignore',
      );
      final entries = readJsonl(_errorsPath);
      expect(entries, hasLength(1));
      expect(
        entries.first['fingerprint'],
        equals('scan.threshold_hit.generated_files'),
      );
      expect(entries.first['count'], equals(1));
    });

    test('same fingerprint increments count, not adds new entry', () {
      const fp = 'scan.threshold_hit.generated_files';
      logger.logError(
        command: 'scan',
        errorType: 'threshold_hit',
        fingerprint: fp,
        reason: 'too many files',
      );
      logger.logError(
        command: 'scan',
        errorType: 'threshold_hit',
        fingerprint: fp,
        reason: 'too many files',
      );
      final entries = readJsonl(_errorsPath);
      expect(entries, hasLength(1));
      expect(entries.first['count'], equals(2));
    });

    test('rotation: interactions exceed max drops oldest', () {
      // Override with a low-max logger by writing pre-existing entries
      final manyEntries = '${List.generate(
        502,
        (i) => jsonEncode({'ts': 'x', 'command': 'setup', 'n': i, 'outcome': 'ok'}),
      ).join('\n')}\n';
      io.write(_interactionsPath, manyEntries);

      // Simulate new log — recreate logger and log one more
      final l2 = SessionLogger(io: io);
      l2.logInteraction(command: 'new_cmd', outcome: 'ok');

      final entries = readJsonl(_interactionsPath);
      // Should be capped at 500 (rotation trims to 500)
      expect(entries.length, lessThanOrEqualTo(500));
      expect(entries.last['command'], equals('new_cmd'));
    });

    test('sensitive mode abstracts stack trace before write', () {
      final tm = TokenMap();
      final sensitiveLogger = SessionLogger(
        io: io,
        sensitivityMode: true,
        tokenMap: tm,
      );
      sensitiveLogger.logError(
        command: 'scan',
        errorType: 'error',
        fingerprint: 'test.fp',
        reason: 'crash',
        stackTrace: 'at VolumeBloc.process (volume_bloc.dart:42)',
      );
      final entries = readJsonl(_errorsPath);
      final stack = entries.first['stack'] as String;
      expect(stack, isNot(contains('VolumeBloc')));
    });

    test('sensitive mode abstracts reason before write', () {
      // Found real while verifying PR #72's central error catch: this
      // abstracted stackTrace but not reason -- the field every real
      // caller actually populates -- so a sensitive-mode project's error
      // log still leaked raw identifiers through `reason`.
      final tm = TokenMap();
      final sensitiveLogger = SessionLogger(
        io: io,
        sensitivityMode: true,
        tokenMap: tm,
      );
      sensitiveLogger.logError(
        command: 'scan',
        errorType: 'error',
        fingerprint: 'test.fp2',
        reason: 'VolumeBloc.process failed',
      );
      final entries = readJsonl(_errorsPath);
      final reason = entries.first['reason'] as String;
      expect(reason, isNot(contains('VolumeBloc')));
    });

    test('logPerformance writes header row', () {
      logger.logPerformance(command: 'scan', outcome: 'ok', filesScanned: 10);
      final content = io.read(_performancePath);
      expect(content, contains('| command |'));
      expect(content, contains('scan'));
    });

    test('logPerformance rotation caps at 50 entries', () {
      for (var i = 0; i < 52; i++) {
        logger.logPerformance(command: 'cmd_$i', outcome: 'ok');
      }
      final content = io.read(_performancePath);
      final lines = content
          .split('\n')
          .where((l) => l.startsWith('|'))
          .toList();
      // 2 header lines + max 50 data lines
      expect(lines.length, lessThanOrEqualTo(52));
    });
  });

  group('SessionLogger.logStepModels', () {
    const haikuId = 'claude-haiku-4-5-20251001';
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger(io: io);
    });

    AgentCompleted completed({
      AgentModel? intended = AgentModel.haiku,
      List<ModelObservation> models = const [],
    }) =>
        AgentCompleted(
          stepId: 'reader',
          usage: const Usage(),
          intendedModel: intended,
          models: models,
        );

    List<Map<String, dynamic>> records() => [
          for (final line in io.read(_modelsPath).split('\n'))
            if (line.isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
        ];

    test('writes one record per observed model, with the reconciliation', () {
      logger.logStepModels(
        command: 'debug',
        event: completed(models: const [
          ModelObservation(
            observedModelId: haikuId,
            observedContextWindow: 200000,
            observedMaxOutputTokens: 32000,
            inputTokens: 50000,
          ),
          ModelObservation(observedModelId: 'claude-future-9'),
        ]),
      );
      final written = records();
      expect(written.length, 2);
      expect(written.first['command'], 'debug');
      expect(written.first[ModelRecordField.stepId.name], 'reader');
      expect(written.first[ModelRecordField.intended.name], 'haiku');
      expect(written.first[ModelRecordField.resolved.name], 'haiku');
      expect(written.first[ModelRecordField.drift.name], ['maxOutputTokens']);
      expect(written.first[ModelRecordField.contextUsedFraction.name], 0.25);
      expect(written.last[ModelRecordField.resolved.name], isNull);
      expect(written.last[ModelRecordField.drift.name], ['unknownModel']);
    });

    test('the record holds exactly the ModelRecordField keys plus ts, command',
        () {
      logger.logStepModels(
        command: 'debug',
        event: completed(models: const [ModelObservation(observedModelId: haikuId)]),
      );
      expect(
        records().single.keys.toSet(),
        {'ts', 'command', for (final f in ModelRecordField.values) f.name},
      );
    });

    test('writes nothing when the stream named no model', () {
      logger.logStepModels(command: 'debug', event: completed());
      expect(io.fileExists(_modelsPath), isFalse);
    });

    test('writes nothing when the intended model is unknown to the event', () {
      logger.logStepModels(
        command: 'debug',
        event: completed(
          intended: null,
          models: const [ModelObservation(observedModelId: haikuId)],
        ),
      );
      expect(io.fileExists(_modelsPath), isFalse);
    });

    test('readStepModelRecords returns the newest record per step, oldest '
        'step first', () {
      void log(String stepId, String observedId) => logger.logStepModels(
            command: 'debug',
            event: AgentCompleted(
              stepId: stepId,
              usage: const Usage(),
              intendedModel: AgentModel.haiku,
              models: [ModelObservation(observedModelId: observedId)],
            ),
          );
      log('a', 'one');
      log('b', 'two');
      log('a', 'three');
      final records = logger.readStepModelRecords();
      expect(records.map((r) => r[ModelRecordField.stepId.name]), ['b', 'a']);
      final newestA = records.last[ModelRecordField.observation.name] as Map;
      expect(newestA[ModelObservationField.observedModelId.jsonKey], 'three');
    });

    test('readStepModelRecords is empty when nothing was logged', () {
      expect(logger.readStepModelRecords(), isEmpty);
    });

    test('appends across steps and keeps only the newest 500', () {
      for (var step = 0; step < 501; step++) {
        logger.logStepModels(
          command: 'debug',
          event: completed(
            models: [ModelObservation(observedModelId: haikuId, inputTokens: step)],
          ),
        );
      }
      final written = records();
      expect(written.length, 500);
      final first = written.first[ModelRecordField.observation.name] as Map;
      expect(first[ModelObservationField.inputTokens.jsonKey], 1);
    });
  });
}
