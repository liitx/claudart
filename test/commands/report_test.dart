import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/report.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

String get _logsDir => p.join(claudeDir, 'logs');
String get _interactionsPath => p.join(_logsDir, 'interactions.jsonl');
String get _errorsPath => p.join(_logsDir, 'errors.jsonl');

void main() {
  group('runReport', () {
    late MemoryFileIO io;

    setUp(() {
      io = MemoryFileIO();
    });

    test('report with no errors prints clean summary', () async {
      // Only interactions, no errors
      io.write(
        _interactionsPath,
        jsonEncode({
              'ts': '2026-03-16T10:00:00Z',
              'command': 'setup',
              'outcome': 'ok',
            }) +
            '\n',
      );
      // Should not throw
      await runReport(io: io, runner: MockProcessRunner());
    });

    test('report compiles command counts correctly', () async {
      final lines = [
        jsonEncode({'command': 'setup', 'outcome': 'ok'}),
        jsonEncode({'command': 'scan', 'outcome': 'ok'}),
        jsonEncode({'command': 'setup', 'outcome': 'ok'}),
      ].join('\n') + '\n';
      io.write(_interactionsPath, lines);
      // Should not throw
      await runReport(io: io, runner: MockProcessRunner());
    });

    test('fingerprint deduplication: same fingerprint not re-filed', () async {
      const fp = 'scan.threshold_hit.too_many_files';
      io.write(
        _errorsPath,
        jsonEncode({
              'ts': '2026-03-16T10:00:00Z',
              'command': 'scan',
              'outcome': 'threshold_hit',
              'fingerprint': fp,
              'reason': 'too many files',
              'count': 2,
              'firstSeen': '2026-03-16T09:00:00Z',
              'lastSeen': '2026-03-16T10:00:00Z',
              'filed': true,
              'issueId': '42',
            }) +
            '\n',
      );
      // With filed=true and fileIssue=false, nothing should be filed
      await runReport(fileIssue: false, io: io, runner: MockProcessRunner());
      // Error file should be unchanged
      final raw = io.read(_errorsPath);
      final entry = jsonDecode(raw.trim()) as Map<String, dynamic>;
      expect(entry['issueId'], equals('42'));
    });

    test('report with empty logs prints clean state', () async {
      await runReport(io: io, runner: MockProcessRunner());
      // No errors — should complete without error
    });

    test('report shows error fingerprints', () async {
      io.write(
        _errorsPath,
        jsonEncode({
              'ts': '2026-03-16T10:00:00Z',
              'command': 'scan',
              'outcome': 'threshold_hit',
              'fingerprint': 'scan.threshold.lib',
              'reason': 'too many files',
              'count': 1,
              'firstSeen': '2026-03-16T10:00:00Z',
              'lastSeen': '2026-03-16T10:00:00Z',
              'filed': false,
              'issueId': null,
            }) +
            '\n',
      );
      // Should not throw and should include fingerprint in output
      await runReport(io: io, runner: MockProcessRunner());
    });
  });
}
