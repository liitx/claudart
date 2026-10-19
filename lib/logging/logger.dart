import 'dart:convert';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../session/handoff_event.dart';
import '../session/handoff_transition.dart';
import '../session/session_state.dart' show HandoffStatus;
import '../paths.dart';
import '../pipeline/model_observation.dart';
import '../pipeline/pipeline_event.dart' show AgentCompleted;
import '../sensitivity/token_map.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';

const int _maxInteractions = 500;
const int _maxErrors = 200;
const int _maxTransitions = 500;
const int _maxPerformance = 50;

/// A jsonl log may run this many lines past its cap before it is trimmed back
/// to the cap, so the rewrite (the only step concurrent writers can race on)
/// happens once per this many appends, not on every one.
const int _trimSlackLines = 50;
const int _maxModelRecords = 500;

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
  String get _transitionsPath => p.join(_logsDir, 'transitions.jsonl');
  String get _modelsPath => p.join(_logsDir, 'models.jsonl');
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

  /// One handoff status change: which command applied which event, from which
  /// status to which. Enum names only, so nothing here needs masking.
  void logTransition({
    required String command,
    required HandoffTransition transition,
  }) {
    _appendJsonl(
      _transitionsPath,
      {
        'ts': DateTime.now().toUtc().toIso8601String(),
        'command': command,
        ...transition.toJson(),
      },
      _maxTransitions,
    );
  }

  /// For commands that replace or erase the handoff instead of editing its
  /// status line (kill, rotate, teardown, setup): records [event] against
  /// [from]. A move the table lacks is logged `rejected: true` and NOT thrown
  /// -- those commands are deliberately permissive today, and this is the
  /// data on how real use differs from docs/design.md before it is enforced.
  void logHandoffMove({
    required String command,
    required HandoffStatus from,
    required HandoffEvent event,
  }) {
    final to = from.after(event);
    if (to != null) {
      logTransition(
        command: command,
        transition: HandoffTransition(from: from, event: event, to: to),
      );
      return;
    }
    _appendJsonl(
      _transitionsPath,
      {
        'ts': DateTime.now().toUtc().toIso8601String(),
        'command': command,
        'from': from.name,
        'event': event.name,
        'rejected': true,
      },
      _maxTransitions,
    );
  }

  /// One line per model a step ran on: the intended model, what the stream
  /// reported, and how they differ. Read from the completion event, so it
  /// costs no model call; nothing is written when the stream named no model.
  void logStepModels({
    required String command,
    required AgentCompleted event,
  }) {
    final intended = event.intendedModel;
    if (intended == null) return;
    for (final observation in event.models) {
      final reconciliation =
          reconcileModel(intended: intended, observation: observation);
      _appendJsonl(
        _modelsPath,
        {
          'ts': DateTime.now().toUtc().toIso8601String(),
          'command': command,
          ...reconciliation.toRecordJson(stepId: event.stepId),
        },
        _maxModelRecords,
      );
    }
  }

  /// The newest record for each step, oldest step first: what the session's
  /// steps last ran on.
  List<Map<String, dynamic>> readStepModelRecords() {
    final latest = <Object?, Map<String, dynamic>>{};
    for (final record in _readJsonlEntries(_modelsPath)) {
      final stepId = record[ModelRecordField.stepId.name];
      latest.remove(stepId);
      latest[stepId] = record;
    }
    return latest.values.toList();
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

    // Found real while verifying #72: this abstracted stackTrace but not
    // reason, so a sensitive-mode project's error log still leaked raw
    // workspace paths/exception causes through `reason` -- the field
    // every caller actually populates. scan.dart had the identical gap
    // before this fix; both callers get it fixed here, not patched twice.
    String safeReason = reason;
    String? safeStack = stackTrace;
    if (sensitivityMode && tokenMap != null) {
      safeReason = abstractor.abstract(safeReason, tokenMap!, defaultDetector);
      if (safeStack != null) {
        safeStack = abstractor.abstract(safeStack, tokenMap!, defaultDetector);
      }
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
        'reason': safeReason,
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
    // One appended line: nothing is read back or rewritten, so two processes
    // logging at once cannot overwrite each other.
    _io.append(path, '${jsonEncode(entry)}\n');
    _trimIfOver(path, maxLines);
  }

  void _trimIfOver(String path, int maxLines) {
    final lines =
        _io.read(path).split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.length <= maxLines + _trimSlackLines) return;
    _io.write(
      path,
      '${lines.sublist(lines.length - maxLines).join('\n')}\n',
    );
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
