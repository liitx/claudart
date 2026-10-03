import 'dart:convert';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../paths.dart';
import '../process_runner.dart';
import '../ui/render.dart' as render;

const _ghRepo = 'liitx/claudart';
const _issueLabelBase = 'claudart-generated';
const _ghExecutable = 'gh';
const _repoFlag = '--repo';
const _bodyFlag = '--body';
const _labelFlag = '--label';

const _keyFingerprint = 'fingerprint';
const _keyCount = 'count';
const _keyFiled = 'filed';
const _keyIssueId = 'issueId';
const _keyStack = 'stack';
const _keyCommand = 'command';
const _unknownValue = 'unknown';

/// Generates a diagnostic report from log files.
/// With [fileIssue]=true, files/updates GitHub issues via the `gh` CLI.
/// [workspacePath] routes logs to the per-project workspace.
Future<void> runReport({
  bool fileIssue = false,
  FileIO? io,
  ProcessRunner? runner,
  String? workspacePath,
}) async {
  final fileIO = io ?? const RealFileIO();
  final proc = runner ?? const RealProcessRunner();

  final logsDir = workspacePath != null
      ? logsDirFor(workspacePath)
      : logsDirFor(claudeDir);
  final interactionsPath = p.join(logsDir, 'interactions.jsonl');
  final errorsPath = p.join(logsDir, 'errors.jsonl');

  final interactions = _readJsonl(fileIO, interactionsPath);
  final errors = _readJsonl(fileIO, errorsPath);

  print(render.header('CLAUDART DIAGNOSTIC REPORT'));
  print('Interactions logged : ${interactions.length}');
  print('Error entries       : ${errors.length}');

  if (interactions.isNotEmpty) {
    final commands = <String, int>{};
    for (final e in interactions) {
      final cmd = e[_keyCommand] as String? ?? _unknownValue;
      commands[cmd] = (commands[cmd] ?? 0) + 1;
    }
    print('\nCommand usage:');
    for (final entry in commands.entries) {
      print('  ${entry.key.padRight(16)} ${entry.value}x');
    }
  }

  if (errors.isNotEmpty) {
    print('\nErrors by fingerprint:');
    for (final e in errors) {
      final fp = e[_keyFingerprint] as String? ?? '?';
      final count = e[_keyCount] as int? ?? 1;
      final reason = e['reason'] as String? ?? '';
      final filed = e[_keyFiled] as bool? ?? false;
      final issueId = e[_keyIssueId];
      final marker = filed && issueId != null ? ' [#$issueId]' : '';
      print('  $fp  (×$count)$marker');
      if (reason.isNotEmpty) print('    └─ $reason');
    }
  } else {
    print('\n✓ No errors recorded.');
  }

  if (!fileIssue || errors.isEmpty) {
    if (fileIssue && errors.isEmpty) {
      print('\n✓ No errors to file.\n');
    }
    return;
  }

  // File/update issues via gh CLI
  print('\nFiling issues to $_ghRepo...');
  final updatedErrors = List<Map<String, dynamic>>.from(
    errors.map((e) => Map<String, dynamic>.from(e)),
  );

  for (var i = 0; i < updatedErrors.length; i++) {
    final entry = updatedErrors[i];
    final fp = entry[_keyFingerprint] as String? ?? _unknownValue;
    final already = entry[_keyFiled] as bool? ?? false;
    final existingId = entry[_keyIssueId];

    if (already && existingId != null) {
      // Add a comment to existing issue
      final body = _buildComment(entry);
      final result = proc.runSync(_ghExecutable, [
        'issue', 'comment', '$existingId',
        _repoFlag, _ghRepo,
        _bodyFlag, body,
      ]);
      if (result.exitCode == 0) {
        print('  ↺ Updated #$existingId ($fp)');
        entry[_keyCount] = (entry[_keyCount] as int? ?? 1) + 1;
        entry['lastSeen'] = DateTime.now().toUtc().toIso8601String();
      } else {
        print('  ✗ Failed to comment on #$existingId: ${result.stderr}');
      }
    } else {
      // File new issue
      final title = '[claudart] ${entry['outcome'] ?? 'error'}: $fp';
      final body = _buildIssueBody(entry);
      final errorType = entry['outcome'] as String? ?? 'error';
      final result = proc.runSync(_ghExecutable, [
        'issue', 'create',
        _repoFlag, _ghRepo,
        '--title', title,
        _bodyFlag, body,
        _labelFlag, _issueLabelBase,
        _labelFlag, errorType,
      ]);
      if (result.exitCode == 0) {
        final issueUrl = (result.stdout as String).trim();
        final issueId = issueUrl.split('/').last;
        entry[_keyFiled] = true;
        entry[_keyIssueId] = issueId;
        print('  ✓ Filed #$issueId ($fp)');
      } else {
        print('  ✗ Failed to file issue for $fp: ${result.stderr}');
      }
    }
  }

  // Write updated errors back
  final content = '${updatedErrors.map(jsonEncode).join('\n')}\n';
  fileIO.write(errorsPath, content);
  print('\nReport complete.\n');
}

String _buildIssueBody(Map<String, dynamic> entry) {
  final buf = StringBuffer();
  buf.writeln('## claudart diagnostic report');
  buf.writeln();
  buf.writeln('**Fingerprint:** `${entry[_keyFingerprint] ?? '?'}`');
  buf.writeln('**Command:** `${entry[_keyCommand] ?? '?'}`');
  buf.writeln('**Outcome:** `${entry['outcome'] ?? '?'}`');
  buf.writeln('**Reason:** ${entry['reason'] ?? '?'}');
  if (entry['suggestion'] != null) {
    buf.writeln('**Suggestion:** ${entry['suggestion']}');
  }
  buf.writeln('**First seen:** ${entry['firstSeen'] ?? '?'}');
  buf.writeln('**Last seen:** ${entry['lastSeen'] ?? '?'}');
  buf.writeln('**Count:** ${entry[_keyCount] ?? 1}');
  if (entry[_keyStack] != null) {
    buf.writeln();
    buf.writeln('```');
    buf.writeln(entry[_keyStack]);
    buf.writeln('```');
  }
  buf.writeln();
  buf.writeln('> Auto-generated by claudart. Stack traces are abstracted.');
  return buf.toString();
}

String _buildComment(Map<String, dynamic> entry) {
  final now = DateTime.now().toUtc().toIso8601String();
  return 'Recurred at $now (total count: ${entry[_keyCount] ?? '?'})';
}

List<Map<String, dynamic>> _readJsonl(FileIO io, String path) {
  final raw = io.read(path);
  if (raw.isEmpty) return [];
  return raw
      .split('\n')
      .where((l) => l.isNotEmpty)
      .map((l) {
        try {
          return Map<String, dynamic>.from(jsonDecode(l) as Map);
        } on FormatException catch (_) {
          return null;
        }
      })
      .whereType<Map<String, dynamic>>()
      .toList();
}
