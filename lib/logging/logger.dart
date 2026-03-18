import 'dart:convert';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../paths.dart';
import '../sensitivity/token_map.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';

const int _maxInteractions = 500;
const int _maxErrors = 200;
const int _maxPerformance = 50;

/// Appends structured log entries to workspace log files.
class SessionLogger {
  final FileIO _io;
  final bool sensitivityMode;
  final TokenMap? tokenMap;
  final String _logsDir;

  SessionLogger({
    FileIO? io,
    this.sensitivityMode = false,
    this.tokenMap,
    String? workspacePath,
  })  : _io = io ?? const RealFileIO(),
        _logsDir = workspacePath != null
            ? logsDirFor(workspacePath)
            : p.join(claudeDir, 'logs');

  String get _interactionsPath => p.join(_logsDir, 'interactions.jsonl');
  String get _errorsPath => p.join(_logsDir, 'errors.jsonl');
  String get _performancePath => p.join(_logsDir, 'performance.md');

  void logInteraction({
    required String command,
    required String outcome,
    bool? sensitivityModeOverride,
    String? scanScope,
    int? filesScanned,
    int? tokensTotal,
    int? tokensNew,
    double? scanDuration,
    int? durationMs,
    String? platform,
    String? claudartVersion,
  }) {
    final entry = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'command': command,
      'sensitivityMode': sensitivityModeOverride ?? sensitivityMode,
      if (scanScope != null) 'scanScope': scanScope,
      if (filesScanned != null) 'filesScanned': filesScanned,
      if (tokensTotal != null) 'tokensTotal': tokensTotal,
      if (tokensNew != null) 'tokensNew': tokensNew,
      if (scanDuration != null) 'scanDuration': scanDuration,
      if (durationMs != null) 'durationMs': durationMs,
      if (platform != null) 'platform': platform,
      if (claudartVersion != null) 'claudartVersion': claudartVersion,
      'outcome': outcome,
    };
    _appendJsonl(_interactionsPath, entry, _maxInteractions);
  }

  void logError({
    required String command,
    required String errorType,
    required String fingerprint,
    required String reason,
    String? suggestion,
    String? stackTrace,
    Map<String, dynamic>? extra,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    // Check existing for deduplication
    final existing = _readJsonlEntries(_errorsPath);
    final matchIdx =
        existing.indexWhere((e) => e['fingerprint'] == fingerprint);

    String? safeStack = stackTrace;
    if (sensitivityMode && tokenMap != null && safeStack != null) {
      safeStack = abstractor.abstract(safeStack, tokenMap!, defaultDetector);
    }

    if (matchIdx >= 0) {
      final old = Map<String, dynamic>.from(existing[matchIdx]);
      old['count'] = ((old['count'] as int?) ?? 1) + 1;
      old['lastSeen'] = now;
      existing[matchIdx] = old;
    } else {
      final entry = <String, dynamic>{
        'ts': now,
        'command': command,
        'outcome': errorType,
        'fingerprint': fingerprint,
        'reason': reason,
        if (suggestion != null) 'suggestion': suggestion,
        if (safeStack != null) 'stack': safeStack,
        'count': 1,
        'firstSeen': now,
        'lastSeen': now,
        'filed': false,
        'issueId': null,
        ...?extra,
      };
      existing.add(entry);
    }

    _writeJsonl(_errorsPath, existing, _maxErrors);
  }

  void logPerformance({
    required String command,
    required String outcome,
    int? filesScanned,
    Duration? duration,
    int? tokensNew,
  }) {
    final entry = StringBuffer();
    entry.write('| ${DateTime.now().toUtc().toIso8601String()} '
        '| $command '
        '| ${filesScanned ?? '-'} '
        '| ${duration?.inMilliseconds ?? '-'}ms '
        '| ${tokensNew ?? '-'} '
        '| $outcome |');

    final current = _io.read(_performancePath);
    final lines = current.isEmpty
        ? <String>[]
        : current.split('\n').where((l) => l.isNotEmpty).toList();

    if (lines.isEmpty) {
      lines.add(
          '| timestamp | command | filesScanned | duration | tokensNew | outcome |');
      lines.add('|-----------|---------|-------------|----------|-----------|--------|');
    }

    // Data lines start after the 2-line header
    final header = lines.take(2).toList();
    var data = lines.skip(2).toList();
    data.add(entry.toString());

    if (data.length > _maxPerformance) {
      data = data.sublist(data.length - _maxPerformance);
    }

    _io.write(_performancePath, '${[...header, ...data].join('\n')}\n');
  }

  // ---- private helpers ----

  List<Map<String, dynamic>> _readJsonlEntries(String path) {
    final raw = _io.read(path);
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

  void _appendJsonl(
    String path,
    Map<String, dynamic> entry,
    int maxLines,
  ) {
    final existing = _readJsonlEntries(path);
    existing.add(entry);
    _writeJsonl(path, existing, maxLines);
  }

  void _writeJsonl(
    String path,
    List<Map<String, dynamic>> entries,
    int maxLines,
  ) {
    var trimmed = entries;
    if (trimmed.length > maxLines) {
      trimmed = trimmed.sublist(trimmed.length - maxLines);
    }
    final content = '${trimmed.map(jsonEncode).join('\n')}\n';
    _io.write(path, content);
  }
}
