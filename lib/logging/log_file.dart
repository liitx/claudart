// log_file.dart — the files claudart writes under a workspace's logs directory.
//
// One variant per file, and the only place a file name is spelled out. The
// logger, the report command and the tests all reach a log through this enum,
// so a new log file is declared here first and no caller carries its own copy
// of a name.

import 'package:path/path.dart' as p;

/// A log file inside a workspace's logs directory.
enum LogFile {
  /// One record per command run: what ran and how it ended.
  interactions,

  /// Failures, deduplicated by fingerprint and counted.
  errors,

  /// Every move of the handoff state machine.
  transitions,

  /// Which model each step ran on, and whether its models add up.
  models,

  /// Every pipeline event: each step's start, end and failure.
  steps,

  /// Timing of command runs, as a table.
  performance;

  /// The file name inside the logs directory.
  String get fileName => switch (this) {
        LogFile.interactions => 'interactions.jsonl',
        LogFile.errors => 'errors.jsonl',
        LogFile.transitions => 'transitions.jsonl',
        LogFile.models => 'models.jsonl',
        LogFile.steps => 'steps.jsonl',
        LogFile.performance => 'performance.md',
      };
}

/// The path of [file] inside [logsDirectory].
String logFilePath(String logsDirectory, LogFile file) =>
    p.join(logsDirectory, file.fileName);
