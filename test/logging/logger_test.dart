import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/model_observation.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/sensitivity/token_map.dart';
import 'package:path/path.dart' as p;
import '../helpers/mocks.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/log_protection.dart';
import '../helpers/project_fixture.dart';

String get _logsDir => p.join(claudeDir, 'logs');
String get _interactionsPath => logFilePath(_logsDir, LogFile.interactions);
String get _errorsPath => logFilePath(_logsDir, LogFile.errors);
String get _transitionsPath => logFilePath(_logsDir, LogFile.transitions);
String get _performancePath => logFilePath(_logsDir, LogFile.performance);
String get _modelsPath => logFilePath(_logsDir, LogFile.models);
String get _stepsPath => logFilePath(_logsDir, LogFile.steps);

void main() {
  group('SessionLogger', () {
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger.plain(io: io);
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

    // The log may run 50 lines past its 500-line cap before it is trimmed back
    // to 500, so the rewrite happens once per 50 appends, not on every one.
    test('rotation: past cap plus slack, the newest 500 remain', () {
      final manyEntries = '${List.generate(
        551,
        (i) => jsonEncode({'ts': 'x', 'command': 'setup', 'n': i, 'outcome': 'ok'}),
      ).join('\n')}\n';
      io.write(_interactionsPath, manyEntries);

      // Simulate new log — recreate logger and log one more
      final l2 = SessionLogger.plain(io: io);
      l2.logInteraction(command: 'new_cmd', outcome: 'ok');

      final entries = readJsonl(_interactionsPath);
      expect(entries.length, 500);
      expect(entries.last['command'], equals('new_cmd'));
      expect(entries.first['n'], 52);
    });

    test('rotation: within the slack nothing is trimmed', () {
      final within = '${List.generate(
        549,
        (i) => jsonEncode(
          {'ts': 'x', 'command': 'setup', 'n': i, 'outcome': 'ok'},
        ),
      ).join('\n')}\n';
      io.write(_interactionsPath, within);
      SessionLogger.plain(io: io)
          .logInteraction(command: 'new_cmd', outcome: 'ok');
      final entries = readJsonl(_interactionsPath);
      expect(entries.length, 550);
      expect(entries.first['n'], 0);
    });

    test('sensitive mode abstracts stack trace before write', () {
      final tm = TokenMap();
      final sensitiveLogger = SessionLogger.abstracted(tokenMap: tm, io: io);
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
      final sensitiveLogger = SessionLogger.abstracted(tokenMap: tm, io: io);
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

    const performanceHeader = '| timestamp | command | filesScanned | duration '
        '| tokensNew | outcome |';
    const performanceDivider =
        '|-----------|---------|-------------|----------|-----------|--------|';

    List<String> performanceTable() => io
        .read(_performancePath)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();

    test('logPerformance starts the table with a header and a divider row',
        () {
      logger.logPerformance(command: 'scan', outcome: 'ok', filesScanned: 10);
      final table = performanceTable();
      expect(table[0], performanceHeader);
      expect(table[1], performanceDivider);
      expect(table.length, 3);
      expect(table[2], contains('| scan | 10 |'));
    });

    test('logPerformance keeps every row, in order, under the header', () {
      for (final command in ['one', 'two', 'three']) {
        logger.logPerformance(command: command, outcome: 'ok');
      }
      final table = performanceTable();
      expect(table.length, 5);
      expect(table.sublist(2).map((row) => row.split('|')[2].trim()),
          ['one', 'two', 'three']);
    });

    test('logPerformance rotation keeps the header and the newest 50 rows', () {
      for (var i = 0; i < 52; i++) {
        logger.logPerformance(command: 'cmd_$i', outcome: 'ok');
      }
      final table = performanceTable();
      expect(table.length, 52);
      expect(table[0], performanceHeader);
      expect(table[1], performanceDivider);
      expect(table[2], contains('| cmd_2 |'));
      expect(table.last, contains('| cmd_51 |'));
    });
  });

  group('SessionLogger.logStepModels', () {
    const haikuId = 'claude-haiku-4-5-20251001';
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger.plain(io: io);
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

    test('a helper call beside the intended model is logged as incidental, '
        'not drift', () {
      logger.logStepModels(
        command: 'suggest',
        event: AgentCompleted(
          stepId: 'reasoner',
          usage: const Usage(),
          intendedModel: AgentModel.sonnet,
          models: [
            ModelObservation(observedModelId: AgentModel.haiku.slug),
            ModelObservation(observedModelId: AgentModel.sonnet.slug),
          ],
        ),
      );
      final byRole = {
        for (final record in records())
          record[ModelRecordField.role.name]: record,
      };
      expect(
        byRole.keys.toSet(),
        {
          ObservedModelRole.stepModel.name,
          ObservedModelRole.incidentalHelper.name,
        },
      );
      final helper = byRole[ObservedModelRole.incidentalHelper.name]!;
      expect(
        helper[ModelRecordField.drift.name] as List,
        isNot(contains(ModelDriftKind.differsFromIntended.name)),
      );
    });

    test('every record of a run carries the same accounting', () {
      logger.logStepModels(
        command: 'suggest',
        event: AgentCompleted(
          stepId: 'reasoner',
          usage: const Usage(),
          intendedModel: AgentModel.sonnet,
          models: [
            const ModelObservation(observedModelId: 'not-a-declared-model'),
            ModelObservation(observedModelId: AgentModel.sonnet.slug),
          ],
        ),
      );
      expect(
        records().map((record) => record[ModelRecordField.accounting.name]),
        everyElement([ModelAccountingFinding.unknownModelObserved.name]),
      );
    });

    test('a run that adds up is logged with an empty accounting', () {
      logger.logStepModels(
        command: 'suggest',
        event: AgentCompleted(
          stepId: 'reasoner',
          usage: const Usage(),
          intendedModel: AgentModel.sonnet,
          models: [ModelObservation(observedModelId: AgentModel.sonnet.slug)],
        ),
      );
      expect(
        records().single[ModelRecordField.accounting.name],
        isEmpty,
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

    // The row `claudart status` shows for a step is the model the step ran on.
    // A helper call is never that row, whichever order the CLI listed them in.
    test('readStepModelRecords never lets a helper call replace the step model',
        () {
      logger.logStepModels(
        command: 'suggest',
        event: AgentCompleted(
          stepId: 'reasoner',
          usage: const Usage(),
          intendedModel: AgentModel.sonnet,
          models: [
            ModelObservation(observedModelId: AgentModel.sonnet.slug),
            ModelObservation(observedModelId: AgentModel.haiku.slug),
          ],
        ),
      );
      final shown = logger.readStepModelRecords().single;
      final observation = shown[ModelRecordField.observation.name] as Map;
      expect(
        observation[ModelObservationField.observedModelId.jsonKey],
        AgentModel.sonnet.slug,
      );
      expect(
        shown[ModelRecordField.role.name],
        ObservedModelRole.stepModel.name,
      );
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

    test('appends across steps; past the cap plus slack, the newest 500 remain',
        () {
      for (var step = 0; step < 551; step++) {
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
      expect(first[ModelObservationField.inputTokens.jsonKey], 51);
    });
  });

  group('SessionLogger with concurrent writers (real processes)', () {
    const writers = 4;
    const entriesPerWriter = 100;
    const writerScript = 'test/helpers/append_log_lines.dart';

    test('no appended line is lost when several processes log at once',
        () async {
      final dir = Directory.systemTemp.createTempSync('claudart_log_race_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final results = await Future.wait([
        for (var writer = 0; writer < writers; writer++)
          Process.run(Platform.resolvedExecutable, [
            writerScript,
            dir.path,
            '$writer',
            '$entriesPerWriter',
          ]),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }

      final lines = File(
        logFilePath(logsDirFor(dir.path), LogFile.interactions),
      )
          .readAsLinesSync()
          .where((l) => l.isNotEmpty);
      expect(lines.length, writers * entriesPerWriter);
      for (final line in lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    }, timeout: const Timeout(Duration(seconds: 90)));

    // logError is a read-modify-write (deduplicate by fingerprint, count it):
    // without a lock around it, two processes read the same state and one
    // update is lost.
    Future<List<Map<String, dynamic>>> runErrorWriters(
      String mode, {
      int writers = 4,
      int perWriter = 25,
    }) async {
      final dir = Directory.systemTemp.createTempSync('claudart_err_race_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final results = await Future.wait([
        for (var writer = 0; writer < writers; writer++)
          Process.run(Platform.resolvedExecutable, [
            'test/helpers/log_errors.dart',
            dir.path,
            '$writer',
            '$perWriter',
            mode,
          ]),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      return [
        for (final line in File(
          logFilePath(logsDirFor(dir.path), LogFile.errors),
        )
            .readAsLinesSync())
          if (line.isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
      ];
    }

    test('one fingerprint logged from several processes keeps its full count',
        () async {
      final entries = await runErrorWriters('shared');
      expect(entries.length, 1);
      expect(entries.single['count'], 4 * 25);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('timing rows from several processes all survive', () async {
      final dir = Directory.systemTemp.createTempSync('claudart_perf_race_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final results = await Future.wait([
        for (var writer = 0; writer < 4; writer++)
          Process.run(Platform.resolvedExecutable, [
            'test/helpers/log_performance_rows.dart',
            dir.path,
            '$writer',
            '10',
          ]),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      final rows = File(logFilePath(logsDirFor(dir.path), LogFile.performance))
          .readAsLinesSync()
          .where((l) => l.startsWith('| ') && !l.contains('timestamp'));
      expect(rows.length, 4 * 10);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('distinct fingerprints from several processes all survive',
        () async {
      final entries = await runErrorWriters('distinct');
      expect(entries.length, 4 * 25);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  // The persisted keys are the enum names, so renaming a variant would change
  // what is written: each key is pinned here as a literal.
  group('LogEntryField keys', () {
    const keys = <LogEntryField, String>{
      LogEntryField.ts: 'ts',
      LogEntryField.command: 'command',
      LogEntryField.outcome: 'outcome',
      LogEntryField.sensitivityMode: 'sensitivityMode',
      LogEntryField.scanScope: 'scanScope',
      LogEntryField.filesScanned: 'filesScanned',
      LogEntryField.tokensTotal: 'tokensTotal',
      LogEntryField.tokensNew: 'tokensNew',
      LogEntryField.scanDuration: 'scanDuration',
      LogEntryField.durationMs: 'durationMs',
      LogEntryField.platform: 'platform',
      LogEntryField.claudartVersion: 'claudartVersion',
      LogEntryField.fingerprint: 'fingerprint',
      LogEntryField.reason: 'reason',
      LogEntryField.suggestion: 'suggestion',
      LogEntryField.stack: 'stack',
      LogEntryField.count: 'count',
      LogEntryField.firstSeen: 'firstSeen',
      LogEntryField.lastSeen: 'lastSeen',
      LogEntryField.filed: 'filed',
      LogEntryField.issueId: 'issueId',
      LogEntryField.rejected: 'rejected',
      LogEntryField.kind: 'kind',
      LogEntryField.stepId: 'stepId',
      LogEntryField.detail: 'detail',
      LogEntryField.failureType: 'failureType',
    };

    for (final field in LogEntryField.values) {
      test('${field.name} is written as "${keys[field]}"', () {
        expect(field.name, keys[field]);
      });
    }

    test('every variant has a pinned key', () {
      expect(keys.keys.toSet(), LogEntryField.values.toSet());
    });
  });

  group('SessionLogger entries: optional fields appear only when passed', () {
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger.plain(io: io);
    });

    Map<String, dynamic> lastLine(String path) =>
        jsonDecode(io.read(path).trim().split('\n').last)
            as Map<String, dynamic>;

    // logInteraction with a fixed command and outcome and one optional field.
    void interaction(
      SessionLogger l, {
      String? scanScope,
      int? filesScanned,
      int? tokensTotal,
      int? tokensNew,
      double? scanDuration,
      int? durationMs,
      String? platform,
      String? claudartVersion,
    }) =>
        l.logInteraction(
          command: 'c',
          outcome: 'o',
          scanScope: scanScope,
          filesScanned: filesScanned,
          tokensTotal: tokensTotal,
          tokensNew: tokensNew,
          scanDuration: scanDuration,
          durationMs: durationMs,
          platform: platform,
          claudartVersion: claudartVersion,
        );

    // One case per optional field of logInteraction: how to pass it, and the
    // value it must be recorded as.
    final interactionFields =
        <LogEntryField, ({void Function(SessionLogger) pass, Object value})>{
      LogEntryField.scanScope: (
        pass: (l) => interaction(l, scanScope: 'lib'),
        value: 'lib',
      ),
      LogEntryField.filesScanned: (
        pass: (l) => interaction(l, filesScanned: 42),
        value: 42,
      ),
      LogEntryField.tokensTotal: (
        pass: (l) => interaction(l, tokensTotal: 10),
        value: 10,
      ),
      LogEntryField.tokensNew: (
        pass: (l) => interaction(l, tokensNew: 3),
        value: 3,
      ),
      LogEntryField.scanDuration: (
        pass: (l) => interaction(l, scanDuration: 1.5),
        value: 1.5,
      ),
      LogEntryField.durationMs: (
        pass: (l) => interaction(l, durationMs: 99),
        value: 99,
      ),
      LogEntryField.platform: (
        pass: (l) => interaction(l, platform: 'macos'),
        value: 'macos',
      ),
      LogEntryField.claudartVersion: (
        pass: (l) => interaction(l, claudartVersion: '1.2.3'),
        value: '1.2.3',
      ),
    };

    interactionFields.forEach((field, how) {
      test('${field.name} is recorded when passed', () {
        how.pass(logger);
        expect(lastLine(_interactionsPath)[field.name], how.value);
      });

      test('${field.name} is absent when not passed', () {
        logger.logInteraction(command: 'c', outcome: 'o');
        expect(lastLine(_interactionsPath).containsKey(field.name), isFalse);
      });
    });

    void logAnError({
      String fingerprint = 'fp',
      String? suggestion,
      String? stackTrace,
      Map<String, dynamic>? extra,
    }) =>
        logger.logError(
          command: 'cmd',
          errorType: 'boom',
          fingerprint: fingerprint,
          reason: 'why',
          suggestion: suggestion,
          stackTrace: stackTrace,
          extra: extra,
        );

    test('an error records suggestion only when given', () {
      logAnError(suggestion: 'try again');
      expect(lastLine(_errorsPath)[LogEntryField.suggestion.name], 'try again');
      io.delete(_errorsPath);
      logAnError();
      expect(
        lastLine(_errorsPath).containsKey(LogEntryField.suggestion.name),
        isFalse,
      );
    });

    test('an error records the stack only when given', () {
      logAnError(stackTrace: 'at a.dart:1');
      expect(lastLine(_errorsPath)[LogEntryField.stack.name], 'at a.dart:1');
      io.delete(_errorsPath);
      logAnError();
      expect(
        lastLine(_errorsPath).containsKey(LogEntryField.stack.name),
        isFalse,
      );
    });

    test('extra fields are merged into a new error entry', () {
      logAnError(extra: {'scanned': 7});
      expect(lastLine(_errorsPath)['scanned'], 7);
    });

    test('the same fingerprint is one entry with a growing count', () {
      logAnError();
      logAnError();
      logAnError();
      final lines = io.read(_errorsPath).trim().split('\n');
      expect(lines.length, 1);
      final entry = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(entry[LogEntryField.count.name], 3);
    });

    test('a different fingerprint is a separate entry', () {
      logAnError(fingerprint: 'one');
      logAnError(fingerprint: 'two');
      expect(io.read(_errorsPath).trim().split('\n').length, 2);
    });

    test('a new error starts at count 1, unfiled, with no issue', () {
      logAnError();
      final entry = lastLine(_errorsPath);
      expect(entry[LogEntryField.count.name], 1);
      expect(entry[LogEntryField.filed.name], isFalse);
      expect(entry[LogEntryField.issueId.name], isNull);
    });
  });

  // Every pipeline event is logged, whatever its kind, so a failure, a timeout
  // or a step that never finished leaves a record. A failed step is also
  // written to the error log with its type, so errors.jsonl names it.
  group('$SessionLogger.forEntry', () {
    const reason = 'VolumeBloc timed out';
    const failed = AgentFailed(
      stepId: 'reader',
      reason: reason,
      failureType: FailureType.stepTimedOut,
    );

    RegistryEntry entryFor({required bool sensitive}) => RegistryEntry(
          name: 'my-app',
          projectRoot: ProjectFixture.root,
          workspacePath: ProjectFixture.workspace,
          createdAt: '2026-01-01',
          lastSession: '2026-03-15',
          sensitivityMode: sensitive,
        );

    /// The step log and the error log of the project, after [failed] is logged.
    String logged(MemoryFileIO io, {required bool sensitive}) {
      SessionLogger.forEntry(entryFor(sensitive: sensitive), io: io)
          .logPipelineEvent(command: 'debug', event: failed);
      final logs = logsDirFor(ProjectFixture.workspace);
      return io.read(logFilePath(logs, LogFile.steps)) +
          io.read(logFilePath(logs, LogFile.errors));
    }

    test('a project that is not sensitive is logged as is', () {
      expect(logged(MemoryFileIO(), sensitive: false), contains('VolumeBloc'));
    });

    test('a sensitive project with a readable token map is abstracted', () {
      final io = MemoryFileIO(
        files: {tokenMapPathFor(ProjectFixture.workspace): '{}'},
      );
      expect(logged(io, sensitive: true), isNot(contains('VolumeBloc')));
    });

    test('a sensitive project with no token map yet is still abstracted', () {
      expect(
        logged(MemoryFileIO(), sensitive: true),
        isNot(contains('VolumeBloc')),
      );
    });

    test('a sensitive project with an unreadable token map logs no text', () {
      final io = MemoryFileIO(
        files: {tokenMapPathFor(ProjectFixture.workspace): '{not valid json'},
      );
      final text = logged(io, sensitive: true);
      expect(text, isNot(contains('VolumeBloc')));
      expect(text, contains(redactedLogText));
    });

    test('the failure itself is still named by its type when redacted', () {
      final io = MemoryFileIO(
        files: {tokenMapPathFor(ProjectFixture.workspace): '{not valid json'},
      );
      expect(
        logged(io, sensitive: true),
        contains(FailureType.stepTimedOut.name),
      );
    });
  });

  group('$SessionLogger.labelOnly', () {
    test('writes the redaction marker for a reason and drops the stack', () {
      final io = MemoryFileIO();
      SessionLogger.labelOnly(io: io).logError(
        command: 'scan',
        errorType: 'error',
        fingerprint: 'scan.fp',
        reason: 'VolumeBloc.process failed',
        stackTrace: 'at VolumeBloc.process',
      );
      final entry = jsonDecode(io.read(_errorsPath).trim())
          as Map<String, dynamic>;
      expect(entry[LogEntryField.reason.name], redactedLogText);
      expect(entry.containsKey(LogEntryField.stack.name), isFalse);
    });
  });

  group('$SessionLogger.logPipelineEvent', () {
    late MemoryFileIO io;
    late SessionLogger logger;

    setUp(() {
      io = MemoryFileIO();
      logger = SessionLogger.plain(io: io);
    });

    final eventsByKind = <PipelineEventKind, PipelineEvent>{
      PipelineEventKind.agentStarted: const AgentStarted(
        stepId: 'reader',
        label: 'Reading',
        model: AgentModel.haiku,
        displayStep: 2,
        displayTotal: 4,
      ),
      PipelineEventKind.agentCompleted: const AgentCompleted(
        stepId: 'reader',
        usage: Usage(),
        durationMs: 1234,
      ),
      PipelineEventKind.agentFailed: const AgentFailed(
        stepId: 'reader',
        reason: 'timed out',
        failureType: FailureType.stepTimedOut,
      ),
      PipelineEventKind.agentEscalating:
          const AgentEscalating(stepId: 'lookup', question: 'which file?'),
      PipelineEventKind.agentResumed: const AgentResumed(stepId: 'lookup'),
      PipelineEventKind.planDraft: const PlanDraft(plan: 'the plan'),
      PipelineEventKind.awaitingApproval: const AwaitingApproval(),
      PipelineEventKind.pipelineCompleted: const PipelineCompleted(
        ctx: PipelineContext(
          projectRoot: ProjectFixture.root,
          bug: '',
          expected: '',
          files: [],
        ),
      ),
    };

    List<Map<String, dynamic>> records(String path) => [
          for (final line in io.read(path).split('\n'))
            if (line.isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
        ];

    test('every PipelineEventKind has an event in this spec', () {
      expect(eventsByKind.keys.toSet(), PipelineEventKind.values.toSet());
    });

    eventsByKind.forEach((kind, event) {
      test('${kind.name} is logged with its kind and command', () {
        logger.logPipelineEvent(command: 'debug', event: event);
        final record = records(_stepsPath).single;
        expect(record[LogEntryField.kind.name], kind.name);
        expect(record[LogEntryField.command.name], 'debug');
        expect(record[LogEntryField.ts.name], isNotEmpty);
      });
    });

    test('a completed step logs its duration as the detail', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.agentCompleted]!,
      );
      final record = records(_stepsPath).single;
      expect(record[LogEntryField.stepId.name], 'reader');
      expect(record[LogEntryField.detail.name], 1234);
    });

    test('an event that belongs to no step logs no step id', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.planDraft]!,
      );
      expect(records(_stepsPath).single.containsKey(
        LogEntryField.stepId.name,
      ), isFalse);
    });

    test('a failed step logs its failure type', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.agentFailed]!,
      );
      expect(
        records(_stepsPath).single[LogEntryField.failureType.name],
        FailureType.stepTimedOut.name,
      );
    });

    test('a failed step is also written to the error log, by type', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.agentFailed]!,
      );
      final error = records(_errorsPath).single;
      expect(
        error[LogEntryField.outcome.name],
        FailureType.stepTimedOut.errorType.name,
      );
      expect(
        error[LogEntryField.fingerprint.name],
        '${FailureType.stepTimedOut.errorType.name}.reader.'
        '${FailureType.stepTimedOut.name}',
      );
      expect(error[LogEntryField.reason.name], 'timed out');
      expect(
        error[LogEntryField.suggestion.name],
        FailureType.stepTimedOut.suggestedAction,
      );
    });

    test('a failed step with no reason logs the failure type label', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: const AgentFailed(
          stepId: 'reader',
          failureType: FailureType.stepProducedNoResult,
        ),
      );
      expect(
        records(_errorsPath).single[LogEntryField.reason.name],
        FailureType.stepProducedNoResult.label,
      );
    });

    for (final kind in PipelineEventKind.values) {
      if (kind == PipelineEventKind.agentFailed) continue;
      test('${kind.name} writes no error', () {
        logger.logPipelineEvent(command: 'debug', event: eventsByKind[kind]!);
        expect(io.fileExists(_errorsPath), isFalse);
      });
    }

    test('events are appended in the order they happened', () {
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.agentStarted]!,
      );
      logger.logPipelineEvent(
        command: 'debug',
        event: eventsByKind[PipelineEventKind.agentCompleted]!,
      );
      expect(
        records(_stepsPath).map((r) => r[LogEntryField.kind.name]),
        [
          PipelineEventKind.agentStarted.name,
          PipelineEventKind.agentCompleted.name,
        ],
      );
    });

    test('logPipelineEvents logs every event of a stream', () async {
      final controller = StreamController<PipelineEvent>();
      final subscription =
          logger.logPipelineEvents(controller.stream, command: 'debug');
      final done = subscription.asFuture<void>();
      eventsByKind.values.forEach(controller.add);
      await controller.close();
      await done;
      await subscription.cancel();
      expect(records(_stepsPath), hasLength(PipelineEventKind.values.length));
    });

    test('logPipelineEvents also logs the models of a completed step',
        () async {
      final controller = StreamController<PipelineEvent>();
      final subscription =
          logger.logPipelineEvents(controller.stream, command: 'debug');
      final done = subscription.asFuture<void>();
      controller.add(const AgentCompleted(
        stepId: 'reader',
        usage: Usage(),
        intendedModel: AgentModel.haiku,
        models: [ModelObservation(observedModelId: 'claude-future-9')],
      ));
      await controller.close();
      await done;
      await subscription.cancel();
      expect(records(_modelsPath), isNotEmpty);
    });

    group('detail of a failure that names a workspace identifier', () {
      const failed = AgentFailed(
        stepId: 'reader',
        reason: 'VolumeBloc.process failed',
        failureType: FailureType.stepTimedOut,
      );

      String loggedDetail(SessionLogger sessionLogger) {
        sessionLogger.logPipelineEvent(command: 'debug', event: failed);
        return records(_stepsPath).single[LogEntryField.detail.name] as String;
      }

      test('is abstracted in sensitive mode', () {
        final sensitiveLogger = SessionLogger.abstracted(
          tokenMap: TokenMap(),
          io: io,
        );
        expect(loggedDetail(sensitiveLogger), isNot(contains('VolumeBloc')));
      });

      test('is written as is when sensitive mode is off', () {
        final plainLogger = SessionLogger.plain(io: io);
        expect(loggedDetail(plainLogger), contains('VolumeBloc'));
      });
    });
  });
}
