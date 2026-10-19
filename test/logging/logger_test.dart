import 'dart:convert';
import 'dart:io';
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

    // The log may run 50 lines past its 500-line cap before it is trimmed back
    // to 500, so the rewrite happens once per 50 appends, not on every one.
    test('rotation: past cap plus slack, the newest 500 remain', () {
      final manyEntries = '${List.generate(
        551,
        (i) => jsonEncode({'ts': 'x', 'command': 'setup', 'n': i, 'outcome': 'ok'}),
      ).join('\n')}\n';
      io.write(_interactionsPath, manyEntries);

      // Simulate new log — recreate logger and log one more
      final l2 = SessionLogger(io: io);
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
      SessionLogger(io: io).logInteraction(command: 'new_cmd', outcome: 'ok');
      final entries = readJsonl(_interactionsPath);
      expect(entries.length, 550);
      expect(entries.first['n'], 0);
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

      final lines = File(p.join(logsDirFor(dir.path), 'interactions.jsonl'))
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
        for (final line in File(p.join(logsDirFor(dir.path), 'errors.jsonl'))
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
      final rows = File(p.join(logsDirFor(dir.path), 'performance.md'))
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
      logger = SessionLogger(io: io);
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
}
