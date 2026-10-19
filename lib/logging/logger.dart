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

/// The keys of a session log entry; the names are the keys. (The keys of a
/// transition are [HandoffTransitionField]'s, of a model record
/// [ModelRecordField]'s.)
enum LogEntryField {
  ts,
  command,
  outcome,
  sensitivityMode,
  scanScope,
  filesScanned,
  tokensTotal,
  tokensNew,
  scanDuration,
  durationMs,
  platform,
  claudartVersion,
  fingerprint,
  reason,
  suggestion,
  stack,
  count,
  firstSeen,
  lastSeen,
  filed,
  issueId,
  rejected;
}

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
      LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
      LogEntryField.command.name: command,
      LogEntryField.sensitivityMode.name: sensitivityModeOverride ?? sensitivityMode,
      if (scanScope != null) LogEntryField.scanScope.name: scanScope,
      if (filesScanned != null) LogEntryField.filesScanned.name: filesScanned,
      if (tokensTotal != null) LogEntryField.tokensTotal.name: tokensTotal,
      if (tokensNew != null) LogEntryField.tokensNew.name: tokensNew,
      if (scanDuration != null) LogEntryField.scanDuration.name: scanDuration,
      if (durationMs != null) LogEntryField.durationMs.name: durationMs,
      if (platform != null) LogEntryField.platform.name: platform,
      if (claudartVersion != null) LogEntryField.claudartVersion.name: claudartVersion,
      LogEntryField.outcome.name: outcome,
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
        LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
        LogEntryField.command.name: command,
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
        LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
        LogEntryField.command.name: command,
        HandoffTransitionField.from.name: from.name,
        HandoffTransitionField.event.name: event.name,
        LogEntryField.rejected.name: true,
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
          LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
          LogEntryField.command.name: command,
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
    // Deduplicating is read, change, rewrite: held under a lock so two
    // processes cannot read the same state and lose one's update.
    _io.withExclusiveLock(_errorsPath, () {
      // Check existing for deduplication
      final existing = _readJsonlEntries(_errorsPath);
      final matchIdx =
          existing.indexWhere((e) => e[LogEntryField.fingerprint.name] == fingerprint);

      // Found real while verifying #72: this abstracted stackTrace but not
      // reason, so a sensitive-mode project's error log still leaked raw
      // workspace paths/exception causes through `reason` -- the field
      // every caller actually populates. scan.dart had the identical gap
      // before this fix; both callers get it fixed here, not patched twice.
      String safeReason = reason;
      String? safeStack = stackTrace;
      if (sensitivityMode && tokenMap != null) {
        safeReason =
            abstractor.abstract(safeReason, tokenMap!, defaultDetector);
        if (safeStack != null) {
          safeStack =
              abstractor.abstract(safeStack, tokenMap!, defaultDetector);
        }
      }

      if (matchIdx >= 0) {
        final old = Map<String, dynamic>.from(existing[matchIdx]);
        old[LogEntryField.count.name] = ((old[LogEntryField.count.name] as int?) ?? 1) + 1;
        old[LogEntryField.lastSeen.name] = now;
        existing[matchIdx] = old;
      } else {
        final entry = <String, dynamic>{
          LogEntryField.ts.name: now,
          LogEntryField.command.name: command,
          LogEntryField.outcome.name: errorType,
          LogEntryField.fingerprint.name: fingerprint,
          LogEntryField.reason.name: safeReason,
          if (suggestion != null) LogEntryField.suggestion.name: suggestion,
          if (safeStack != null) LogEntryField.stack.name: safeStack,
          LogEntryField.count.name: 1,
          LogEntryField.firstSeen.name: now,
          LogEntryField.lastSeen.name: now,
          LogEntryField.filed.name: false,
          LogEntryField.issueId.name: null,
          ...?extra,
        };
        existing.add(entry);
      }

      _writeJsonl(_errorsPath, existing, _maxErrors);
    });
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

    // Read, change, rewrite the table: under a lock, so no row is lost.
    _io.withExclusiveLock(_performancePath, () {
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
    });
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
    // One appended line, then (rarely) a trim that rewrites the file. Both
    // run under one lock: a trim's rename would otherwise orphan an append
    // another process was making to the file it replaced.
    _io.withExclusiveLock(path, () {
      _io.append(path, '${jsonEncode(entry)}\n');
      _trimIfOver(path, maxLines);
    });
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
