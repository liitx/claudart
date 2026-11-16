// timed_source.dart — how long things took, read back from the logs
//
// Claudart has no log of its own for timing: every log row that has a duration
// records it itself (a command run, a gate, a completed step, a seeded proof
// fault). A [TimedSource] names one such place, says which rows of its log are its
// own, and where the duration and the label sit. [readTimedLog] returns typed
// records and, separately, the rows that qualify but cannot be read as a duration:
// a gap is never counted as zero and never dropped. How to add a source:
// docs/templates/timed_source.md.

import '../io/file_io.dart';
import '../pipeline/pipeline_event.dart';
import 'log_file.dart';
import 'logger.dart';
import 'run_diagram.dart' show rowsOfJsonl;

/// A place the logs record how long something took.
enum TimedSource {
  /// A command run: the boundary's row in the interactions log.
  commandRun,

  /// A gate command a command ran.
  gateRun,

  /// A pipeline step that completed.
  stepCompleted,

  /// A fault the proof audit seeded.
  proofFault;

  /// The log that holds this source's rows.
  LogFile get logFile => switch (this) {
        TimedSource.commandRun => LogFile.interactions,
        TimedSource.gateRun => LogFile.gates,
        TimedSource.stepCompleted => LogFile.steps,
        TimedSource.proofFault => LogFile.proofs,
      };

  /// Whether [row] of [logFile] is one of this source's. An outcome row of the
  /// interactions log is not a run; a step that only started took no time yet.
  bool qualifies(Map<String, dynamic> row) => switch (this) {
        TimedSource.commandRun =>
          row[LogEntryField.rowKind.name] == InteractionRowKind.run.name,
        TimedSource.gateRun || TimedSource.proofFault => true,
        TimedSource.stepCompleted =>
          row[LogEntryField.kind.name] == PipelineEventKind.agentCompleted.name,
      };

  /// What the row holds where this source keeps its duration, unchecked.
  Object? rawDurationOf(Map<String, dynamic> row) => switch (this) {
        TimedSource.commandRun ||
        TimedSource.gateRun ||
        TimedSource.proofFault =>
          row[LogEntryField.durationMs.name],
        TimedSource.stepCompleted => row[LogEntryField.detail.name],
      };

  /// What the row holds where this source keeps what it is about, unchecked.
  Object? labelOf(Map<String, dynamic> row) => switch (this) {
        TimedSource.commandRun => row[LogEntryField.command.name],
        TimedSource.gateRun => row[LogEntryField.gate.name],
        TimedSource.stepCompleted => row[LogEntryField.stepId.name],
        TimedSource.proofFault => row[LogEntryField.proof.name],
      };
}

/// Why a row that qualifies could not be read as a duration. The duration is
/// judged first, so a row missing both is [durationMissing].
enum TimingGapReason {
  /// The row has no duration.
  durationMissing,

  /// The duration is not a whole number of milliseconds (text, or fractional).
  durationNotWholeNumber,

  /// The duration is below zero.
  durationNegative,

  /// The row does not say what it is about.
  labelMissing,
}

/// One duration read from a log.
typedef TimedRecord = ({TimedSource source, String label, int durationMs});

/// A row that qualifies for a source but cannot be read as a record.
typedef TimingGap = ({
  TimedSource source,
  TimingGapReason reason,
  Map<String, dynamic> row,
});

/// What one source's log yielded: the records, in the order written, and the
/// gaps.
typedef TimedReading = ({List<TimedRecord> records, List<TimingGap> gaps});

/// The records and gaps of [source]'s log inside [logsDirectory]. A log that
/// does not exist reads as nothing.
TimedReading readTimedLog(
  FileIO io,
  String logsDirectory,
  TimedSource source,
) {
  final records = <TimedRecord>[];
  final gaps = <TimingGap>[];
  final rows = rowsOfJsonl(io.read(logFilePath(logsDirectory, source.logFile)));
  for (final row in rows.where(source.qualifies)) {
    final duration = source.rawDurationOf(row);
    final label = source.labelOf(row);
    final reason = _gapReasonOf(duration, label);
    if (reason != null) {
      gaps.add((source: source, reason: reason, row: row));
    } else {
      records.add((
        source: source,
        label: label as String,
        durationMs: duration as int,
      ));
    }
  }
  return (records: records, gaps: gaps);
}

/// Why a duration and a label cannot be read, or null if they can. The duration
/// is judged first.
TimingGapReason? _gapReasonOf(Object? duration, Object? label) {
  if (duration == null) return TimingGapReason.durationMissing;
  if (duration is! int) return TimingGapReason.durationNotWholeNumber;
  if (duration < 0) return TimingGapReason.durationNegative;
  if (label is! String) return TimingGapReason.labelMissing;
  return null;
}

/// What the records of one source and label add up to.
typedef TimingSummary = ({
  TimedSource source,
  String label,
  int runs,
  int totalMs,
  int slowestMs,
  int latestMs,
});

/// One summary per source and label, in the order each first appears; the latest
/// is the last record written, the slowest the largest.
List<TimingSummary> summarizeTimed(List<TimedRecord> records) {
  final order = <(TimedSource, String)>[];
  final byKey = <(TimedSource, String), List<int>>{};
  for (final record in records) {
    final key = (record.source, record.label);
    if (!byKey.containsKey(key)) order.add(key);
    byKey.putIfAbsent(key, () => []).add(record.durationMs);
  }
  return [
    for (final key in order)
      (
        source: key.$1,
        label: key.$2,
        runs: byKey[key]!.length,
        totalMs: byKey[key]!.reduce((a, b) => a + b),
        slowestMs: byKey[key]!.reduce((a, b) => a > b ? a : b),
        latestMs: byKey[key]!.last,
      ),
  ];
}
