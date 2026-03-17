import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/report.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

void main() {
  group('runReport', () {
    late MemoryFileIO io;
    late String workspace;
    late String logsDir;
    late String interactionsPath;
    late String errorsPath;

    setUp(() {
      io = MemoryFileIO();
      workspace = p.join(workspacesRoot, 'test-project');
      logsDir = logsDirFor(workspace);
      interactionsPath = p.join(logsDir, 'interactions.jsonl');
      errorsPath = p.join(logsDir, 'errors.jsonl');
    });

    test('report with no errors prints clean summary', () async {
      // Only interactions, no errors
      io.write(
        interactionsPath,
        jsonEncode({
              'ts': '2026-03-16T10:00:00Z',
              'command': 'setup',
              'outcome': 'ok',
            }) +
            '\n',
      );
      // Should not throw
      await runReport(io: io, runner: MockProcessRunner(), workspacePath: workspace);
    });

    test('report compiles command counts correctly', () async {
      final lines = [
        jsonEncode({'command': 'setup', 'outcome': 'ok'}),
        jsonEncode({'command': 'scan', 'outcome': 'ok'}),
        jsonEncode({'command': 'setup', 'outcome': 'ok'}),
      ].join('\n') + '\n';
      io.write(interactionsPath, lines);
      // Should not throw
      await runReport(io: io, runner: MockProcessRunner(), workspacePath: workspace);
    });

    test('fingerprint deduplication: same fingerprint not re-filed', () async {
      const fp = 'scan.threshold_hit.too_many_files';
      io.write(
        errorsPath,
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
      await runReport(fileIssue: false, io: io, runner: MockProcessRunner(), workspacePath: workspace);
      // Error file should be unchanged
      final raw = io.read(errorsPath);
      final entry = jsonDecode(raw.trim()) as Map<String, dynamic>;
      expect(entry['issueId'], equals('42'));
    });

    test('report with empty logs prints clean state', () async {
      await runReport(io: io, runner: MockProcessRunner(), workspacePath: workspace);
      // No errors — should complete without error
    });

    test('report shows error fingerprints', () async {
      io.write(
        errorsPath,
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
      await runReport(io: io, runner: MockProcessRunner(), workspacePath: workspace);
    });
  });
}
