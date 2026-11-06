// interaction_boundary.dart — every command run leaves one interaction record
//
// The binary runs the chosen command through [runRecorded], so no command can
// be outside it: it records that the run returned, threw, or left the process
// through `exitProcess`, and how long it took. One row per run, whatever the
// command does inside; the richer, per-project rows a command writes itself
// (a kill's warning, a scan's counts) stay where they are.

import '../../io/process_exit.dart';
import '../../logging/logger.dart';
import '../../logging/recorded_outcome.dart';
import 'claudart_command.dart';

/// Runs [body] as [command] and records how it ended in [logger]. A thrown
/// error is recorded and goes on; an exit is recorded before the process
/// leaves; whichever happens first is the one record. [leave] replaces the way
/// out of the process, for a test.
Future<T> runRecorded<T>({
  required ClaudartCommand command,
  required SessionLogger logger,
  required Future<T> Function() body,
  Never Function(int code)? leave,
}) async {
  final clock = Stopwatch()..start();
  var recorded = false;
  void record(RecordedOutcome outcome) {
    if (recorded) return;
    recorded = true;
    logger.logInteraction(
      command: command.wireName,
      outcome: outcome.name,
      durationMs: clock.elapsedMilliseconds,
    );
  }

  return withExitHook(
    beforeExit: (code) =>
        record(code == 0 ? RecordedOutcome.ok : RecordedOutcome.failed),
    leave: leave,
    body: () async {
      try {
        final result = await body();
        record(RecordedOutcome.ok);
        return result;
      } on Object {
        record(RecordedOutcome.failed);
        rethrow;
      }
    },
  );
}
