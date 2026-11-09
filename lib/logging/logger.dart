import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../errors/failure_type.dart';
import '../io/file_io.dart';
import '../session/handoff_event.dart';
import '../session/handoff_transition.dart';
import '../session/session_state.dart' show HandoffStatus;
import '../config/paths.dart';
import '../pipeline/model_observation.dart';
import '../pipeline/pipeline_event.dart'
    show AgentCompleted, AgentFailed, PipelineEvent;
import '../registry.dart';
import '../sensitivity/token_map.dart';
import 'log_file.dart';
import 'log_protection.dart';
import '../session/transition_bus.dart';
import '../io/gate_runner.dart';

/// The version of the shape every log row follows. Raise it when a row's
/// fields change meaning, so a reader can tell old rows from current ones.
const int logSchemaVersion = 1;

const int _maxInteractions = 500;
const int _maxErrors = 200;
const int _maxTransitions = 500;

/// A jsonl log may run this many lines past its cap before it is trimmed back
/// to the cap, so the rewrite (the only step concurrent writers can race on)
/// happens once per this many appends, not on every one.
const int _trimSlackLines = 50;
const int _maxModelRecords = 500;
const int _maxGateRecords = 500;
const int _maxStepRecords = 2000;

/// The keys of a session log entry; the names are the keys. (The keys of a
/// transition are [HandoffTransitionField]'s, of a model record
/// [ModelRecordField]'s.)
enum LogEntryField {
  /// The schema version the row follows; a row without it predates it.
  schema,
  gate,
  evidence,
  shellCommand,
  exitCode,
  outputTail,
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
  rejected,
  kind,
  stepId,
  detail,
  failureType;
}

/// Appends structured log entries to workspace log files.
///
/// Built only through its factories, each of which says how free text is
/// protected ([LogProtection]); [forEntry] chooses for a registered project.
class SessionLogger {
  SessionLogger._(FileIO? io, this._protection, String? workspacePath)
      : _io = io ?? const RealFileIO(),
        _logsDir = workspacePath != null
            ? logsDirFor(workspacePath)
            : p.join(claudeDir, 'logs');

  /// Text is written as it is: a project that is not sensitive, or a log that
  /// holds nothing from a project.
  factory SessionLogger.plain({FileIO? io, String? workspacePath}) =>
      SessionLogger._(io, const PlainLogging(), workspacePath);

  /// Identifiers in text are replaced using [tokenMap] before they are written.
  factory SessionLogger.abstracted({
    required TokenMap tokenMap,
    FileIO? io,
    String? workspacePath,
  }) =>
      SessionLogger._(io, AbstractedLogging(tokenMap), workspacePath);

  /// No free text is written, only what is recorded by type.
  factory SessionLogger.labelOnly({FileIO? io, String? workspacePath}) =>
      SessionLogger._(io, const LabelOnlyLogging(), workspacePath);

  /// The logger for a registered project: plain when it is not sensitive,
  /// abstracted with its token map when it is, and label only when that map
  /// cannot be read, so a sensitive project never has raw text logged.
  factory SessionLogger.forEntry(RegistryEntry entry, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    if (!entry.sensitivityMode) {
      return SessionLogger.plain(
        io: fileIO,
        workspacePath: entry.workspacePath,
      );
    }
    try {
      return SessionLogger.abstracted(
        tokenMap: TokenMap.load(
          tokenMapPathFor(entry.workspacePath),
          io: fileIO,
        ),
        io: fileIO,
        workspacePath: entry.workspacePath,
      );
    } on TokenMapUnreadableException {
      return SessionLogger.labelOnly(
        io: fileIO,
        workspacePath: entry.workspacePath,
      );
    }
  }

  final FileIO _io;
  final LogProtection _protection;
  final String _logsDir;

  String get _interactionsPath => logFilePath(_logsDir, LogFile.interactions);
  String get _errorsPath => logFilePath(_logsDir, LogFile.errors);
  String get _transitionsPath => logFilePath(_logsDir, LogFile.transitions);
  String get _modelsPath => logFilePath(_logsDir, LogFile.models);
  String get _stepsPath => logFilePath(_logsDir, LogFile.steps);
  String get _gatesPath => logFilePath(_logsDir, LogFile.gates);

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
    String? evidence,
  }) {
    final entry = <String, dynamic>{
      LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
      LogEntryField.command.name: command,
      LogEntryField.sensitivityMode.name:
          sensitivityModeOverride ?? _protection.isSensitive,
      if (scanScope != null) LogEntryField.scanScope.name: scanScope,
      if (filesScanned != null) LogEntryField.filesScanned.name: filesScanned,
      if (tokensTotal != null) LogEntryField.tokensTotal.name: tokensTotal,
      if (tokensNew != null) LogEntryField.tokensNew.name: tokensNew,
      if (scanDuration != null) LogEntryField.scanDuration.name: scanDuration,
      if (durationMs != null) LogEntryField.durationMs.name: durationMs,
      if (platform != null) LogEntryField.platform.name: platform,
      if (evidence != null) LogEntryField.evidence.name: evidence,
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

  /// A gate command a command ran: which gate, the command, its exit code, how
  /// long it took and the tail of its output. Free text (the command and its
  /// output) is protected in a sensitive project.
  void logGate({
    required String command,
    required GateKind gate,
    required String shellCommand,
    required GateResult result,
  }) {
    _appendJsonl(
      _gatesPath,
      {
        LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
        LogEntryField.command.name: command,
        LogEntryField.gate.name: gate.name,
        LogEntryField.shellCommand.name: _safe(shellCommand),
        LogEntryField.exitCode.name: result.exitCode,
        LogEntryField.durationMs.name: result.durationMs,
        LogEntryField.outputTail.name: _safe(result.outputTail),
      },
      _maxGateRecords,
    );
  }

  /// A subscriber to status changes that threw: written to the error log under
  /// [FailureType.handoffListenerFailed], naming the subscriber and the move.
  void logListenerFailure({
    required String command,
    required HandoffListenerFailure failure,
  }) {
    const type = FailureType.handoffListenerFailed;
    logError(
      command: command,
      errorType: type.errorType.name,
      fingerprint: '${type.errorType.name}.${failure.listener}.${type.name}',
      reason: '${failure.listener} failed on ${failure.transition.event.name}: '
          '${failure.error}',
      suggestion: type.suggestedAction,
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

  /// One line for a pipeline event: its kind, the step it belongs to, and a
  /// detail (a failure's reason, a completed step's duration). A failed step is
  /// also written to the error log, by its [FailureType], so the error log
  /// names what failed. Whichever kind the event is, it leaves a record.
  void logPipelineEvent({
    required String command,
    required PipelineEvent event,
  }) {
    final record = event.logRecord;
    final detail = record.detail;
    _appendJsonl(
      _stepsPath,
      {
        LogEntryField.ts.name: DateTime.now().toUtc().toIso8601String(),
        LogEntryField.command.name: command,
        LogEntryField.kind.name: record.kind.name,
        if (record.stepId != null) LogEntryField.stepId.name: record.stepId,
        if (detail != null) LogEntryField.detail.name: _safe(detail),
        if (record.failureType != null)
          LogEntryField.failureType.name: record.failureType!.name,
      },
      _maxStepRecords,
    );
    if (event is AgentFailed) {
      final failure = event.failureType;
      logError(
        command: command,
        errorType: failure.errorType.name,
        fingerprint:
            '${failure.errorType.name}.${event.stepId}.${failure.name}',
        reason: event.reason ?? failure.label,
        suggestion: failure.suggestedAction,
      );
    }
  }

  /// Logs every event of [events]: each through [logPipelineEvent], and each
  /// completed step's models through [logStepModels]. Returns the subscription
  /// so a caller can cancel it; a stream that closes ends it.
  StreamSubscription<PipelineEvent> logPipelineEvents(
    Stream<PipelineEvent> events, {
    required String command,
  }) =>
      events.listen((event) {
        logPipelineEvent(command: command, event: event);
        if (event is AgentCompleted) {
          logStepModels(command: command, event: event);
        }
      });

  /// A detail value with its text abstracted in sensitive mode, so a reason
  /// that names a workspace path does not reach the log.
  Object _safe(Object detail) =>
      detail is String ? _protection.protect(detail) : detail;

  /// One line per model a step ran on: the intended model, what the stream
  /// reported, and how they differ. Read from the completion event, so it
  /// costs no model call; nothing is written when the stream named no model.
  void logStepModels({
    required String command,
    required AgentCompleted event,
  }) {
    final intended = event.intendedModel;
    if (intended == null) return;
    for (final reconciliation in reconcileStepModels(
      intended: intended,
      observations: event.models,
    )) {
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
      // A helper call is not what the step ran on, so it never takes the
      // step's row, whatever order the CLI listed the models in.
      if (record[ModelRecordField.role.name] ==
          ObservedModelRole.incidentalHelper.name) {
        continue;
      }
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
      final safeReason = _protection.protect(reason);
      final safeStack =
          stackTrace == null ? null : _protection.protectStack(stackTrace);

      if (matchIdx >= 0) {
        final old = Map<String, dynamic>.from(existing[matchIdx]);
        old[LogEntryField.count.name] = ((old[LogEntryField.count.name] as int?) ?? 1) + 1;
        old[LogEntryField.lastSeen.name] = now;
        existing[matchIdx] = old;
      } else {
        final entry = <String, dynamic>{
          LogEntryField.schema.name: logSchemaVersion,
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
      _io.append(
        path,
        '${jsonEncode({LogEntryField.schema.name: logSchemaVersion, ...entry})}\n',
      );
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
