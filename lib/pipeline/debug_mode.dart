// debug_mode.dart — claudart's debug toggle + per-step trace.
//
// `claudart --debug <command>` flips [setDebugEnabled] at CLI entry so
// every downstream pipeline step records a structured trace to disk.
// `CLAUDART_DEBUG=1` is the env-var equivalent for scripts that can't
// shape argv (CI runners, wrappers). The two sources OR together.
//
// Every label, field, and divider in the trace is a top-level const —
// downstream tooling greps against the same names production writes.
// IO is best-effort: `IOException` swallows so an unwritable log path
// (missing parent, permissions) never aborts a real pipeline run.

import 'dart:convert';
import 'dart:io';

// ── Env-var + path constants ──────────────────────────────────────────────

/// Env var that enables debug-log writes when set to `1`.
const String kClaudartDebugEnvVar = 'CLAUDART_DEBUG';

/// Env var that overrides the default log destination.
const String kClaudartDebugPathEnvVar = 'CLAUDART_DEBUG_PATH';

/// Default destination when no override is provided.
const String kDefaultClaudartDebugLogPath = '/tmp/claudart_debug.log';

/// Value the env var must hold to enable debug mode.
const String kClaudartDebugEnabledValue = '1';

// ── Trace line labels ─────────────────────────────────────────────────────
//
// One const per identifier the trace emits. Production formatting + any
// test/tooling that parses the log MUST reference these — never inline
// string literals.

const String kTraceLabelStep        = 'STEP';
const String kTraceLabelStream      = 'STREAM';
const String kTraceLabelExit        = 'EXIT';
const String kTraceLabelSummary     = 'SUMMARY';
const String kTraceLabelOutputBytes = 'OUTPUT-TEXT-BYTES';
const String kTraceLabelException   = 'EXCEPTION';

const String kTraceFieldModel      = 'model';
const String kTraceFieldWorkingDir = 'workingDir';
const String kTraceFieldSysBytes   = 'sysBytes';
const String kTraceFieldMsgBytes   = 'msgBytes';
const String kTraceFieldInput      = 'in';
const String kTraceFieldCached     = 'cached';
const String kTraceFieldCacheWrite = 'cacheWrite';
const String kTraceFieldOutput     = 'out';
const String kTraceFieldElapsedMs  = 'elapsedMs';
const String kTraceFieldStderr     = 'stderr';
const String kTraceStderrEmpty     = '(none)';

const String kTraceDividerSystemOpen   = '--- SYSTEM PROMPT';
const String kTraceDividerMessageOpen  = '--- MESSAGE';
const String kTraceDividerSectionClose = '---';
const String kTraceDividerEndInput     = '--- END INPUT ---';
const String kTraceByteCountSuffix     = 'bytes';
const String kTraceMessageFullSuffix   = 'full';

// ── Toggle ────────────────────────────────────────────────────────────────

bool _runtimeDebugEnabled = false;

/// Toggled by the CLI when `--debug` is present in argv. Persists for
/// the lifetime of the process so every pipeline step picks it up
/// without an env-var dance.
void setDebugEnabled(bool value) {
  _runtimeDebugEnabled = value;
}

bool _ambientDebugSuppressed = false;

/// What the CLI tells the user when the env var is ignored.
const String kAmbientDebugSuppressedNotice =
    'CLAUDART_DEBUG is ignored: this project is sensitive, and the trace '
    'writes prompts to disk. Pass --debug to trace it anyway.';

/// Set by the CLI for a sensitive project. The env var is ambient (the
/// settings `claudart link` writes set it for every Claude Code session in a
/// project), so it must not write prompts and messages to disk for a
/// sensitive project; the explicit `--debug` flag, a deliberate act, still
/// does.
void suppressAmbientDebug(bool value) {
  _ambientDebugSuppressed = value;
}

/// True when the CLI flag was set, or the env var equals
/// [kClaudartDebugEnabledValue] and a sensitive project has not suppressed it
/// ([suppressAmbientDebug]). [environment] defaults to the process env; tests
/// inject a clean map.
bool debugEnabled({Map<String, String>? environment}) {
  if (_runtimeDebugEnabled) return true;
  if (_ambientDebugSuppressed) return false;
  final env = environment ?? Platform.environment;
  return env[kClaudartDebugEnvVar] == kClaudartDebugEnabledValue;
}

/// Returns the debug log file when debug mode is on, null when off.
/// Callers pass `null` straight through their conditional writes.
File? debugLogFile({Map<String, String>? environment}) {
  if (!debugEnabled(environment: environment)) return null;
  final env = environment ?? Platform.environment;
  final path = env[kClaudartDebugPathEnvVar] ?? kDefaultClaudartDebugLogPath;
  return File(path);
}

// ── UTF-8 byte length ─────────────────────────────────────────────────────

/// UTF-8 byte length of [text]. `String.length` returns UTF-16 code
/// units, which diverge from real byte counts on non-ASCII content;
/// the trace's "bytes" labels demand the honest measurement.
int utf8ByteLength(String text) => utf8.encode(text).length;

// ── Per-step trace ────────────────────────────────────────────────────────

/// Captures the trace for a single pipeline step. Encapsulates the
/// log file, a [Stopwatch] for elapsed-ms, and the formatting rules
/// so the runner in `pipeline_executor.dart` stays focused on the
/// subprocess flow.
///
/// All writes are best-effort: `IOException` is caught so an
/// unwritable log path never aborts a real pipeline run.
/// Sink the trace appends formatted lines to. Production wraps a
/// [File]; tests inject a [StringBuffer] (or any [StringSink]) to
/// inspect the trace output without touching the filesystem.
typedef TraceAppender = void Function(String content);

void _appendToFile(File log, String content) {
  try {
    log.parent.createSync(recursive: true);
    log.writeAsStringSync(content, mode: FileMode.append);
  } on IOException {
    // Best-effort: an unwritable path must not abort the pipeline.
  }
}

class StepDebugTrace {
  StepDebugTrace._({required TraceAppender? appender, required Stopwatch watch})
      : _appender = appender,
        _watch = watch;

  /// Active trace; defers to [debugLogFile] for the on/off decision.
  /// Returns a no-op trace when debug mode is off.
  factory StepDebugTrace.start() {
    final log = debugLogFile();
    return StepDebugTrace._(
      appender: log == null ? null : (content) => _appendToFile(log, content),
      watch: Stopwatch()..start(),
    );
  }

  /// Explicit no-op trace — every method is a no-op. Used in tests
  /// that don't care about output, and as the off-mode default.
  factory StepDebugTrace.disabled() => StepDebugTrace._(
        appender: null,
        watch: Stopwatch(),
      );

  /// Test-only factory: routes every write through [appender] (e.g.
  /// a [StringBuffer.write] callback) so tests inspect the formatted
  /// output without touching the filesystem.
  factory StepDebugTrace.forTesting(TraceAppender appender) =>
      StepDebugTrace._(appender: appender, watch: Stopwatch()..start());

  final TraceAppender? _appender;
  final Stopwatch _watch;

  /// True when this trace will write. Lets callers short-circuit
  /// expensive payload prep when the log is off.
  bool get isActive => _appender != null;

  /// Step header — written first. [systemPrompt] and [message] are
  /// recorded in full. Byte counts are UTF-8.
  void writeStepHeader({
    required String modelAlias,
    required String workingDir,
    required String systemPrompt,
    required String message,
  }) {
    final sysBytes = utf8ByteLength(systemPrompt);
    final msgBytes = utf8ByteLength(message);
    _append(
      '${_lineHead(kTraceLabelStep)}$modelAlias  '
      '$kTraceFieldWorkingDir: $workingDir\n'
      '$kTraceDividerSystemOpen ($sysBytes $kTraceByteCountSuffix) '
      '$kTraceDividerSectionClose\n$systemPrompt\n'
      '$kTraceDividerMessageOpen ($msgBytes $kTraceByteCountSuffix, '
      '$kTraceMessageFullSuffix) $kTraceDividerSectionClose\n$message\n'
      '$kTraceDividerEndInput\n\n',
    );
  }

  /// One stream-json line emitted by the subprocess.
  void writeStreamLine(String line) {
    _append('${_lineHead(kTraceLabelStream)}$line\n');
  }

  /// Process exited.
  void writeExit({required int exitCode, required String stderrText}) {
    final trimmed = stderrText.trim();
    final tail = trimmed.isEmpty ? kTraceStderrEmpty : trimmed;
    _append(
      '${_lineHead(kTraceLabelExit)}$exitCode  '
      '$kTraceFieldStderr: $tail\n\n',
    );
  }

  /// Final summary line — fields keyed by `kTraceField*` consts so
  /// downstream parsers reference the same source.
  void writeSummary({
    required String modelAlias,
    required String systemPrompt,
    required String message,
    required int input,
    required int cacheRead,
    required int cacheCreation,
    required int output,
    required double cost,
    required String resultText,
  }) {
    final sysBytes = utf8ByteLength(systemPrompt);
    final msgBytes = utf8ByteLength(message);
    final outBytes = utf8ByteLength(resultText);
    _append(
      '${_lineHead(kTraceLabelSummary)}'
      '$kTraceFieldModel=$modelAlias  '
      '$kTraceFieldSysBytes=$sysBytes  '
      '$kTraceFieldMsgBytes=$msgBytes  '
      '$kTraceFieldInput=$input  '
      '$kTraceFieldCached=$cacheRead  '
      '$kTraceFieldCacheWrite=$cacheCreation  '
      '$kTraceFieldOutput=$output  '
      '$kTraceFieldElapsedMs=${_watch.elapsedMilliseconds}  '
      '\$${cost.toStringAsFixed(4)}\n'
      '${_lineHead(kTraceLabelOutputBytes)}$outBytes\n\n',
    );
  }

  /// Subprocess threw — record + let the caller decide the user-facing
  /// message.
  void writeException(Object error) {
    _append('${_lineHead(kTraceLabelException)}$error\n\n');
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /// Prefix shared by every line. Fresh timestamp per call so the
  /// trace reflects real-time event order; tooling can subtract pairs
  /// to recover latency between events.
  String _lineHead(String label) =>
      '[${DateTime.now().toIso8601String()}] $label: ';

  void _append(String content) {
    final appender = _appender;
    if (appender == null) return;
    appender(content);
  }
}
