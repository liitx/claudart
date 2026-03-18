import 'dart:convert';
import 'package:test/test.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/sensitivity/token_map.dart';
import 'package:path/path.dart' as p;
import '../helpers/mocks.dart';
import 'package:claudart/paths.dart';

String get _logsDir => p.join(claudeDir, 'logs');
String get _interactionsPath => p.join(_logsDir, 'interactions.jsonl');
String get _errorsPath => p.join(_logsDir, 'errors.jsonl');
String get _performancePath => p.join(_logsDir, 'performance.md');

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
}
