// handoff_store.dart — the one place handoff.md is written
//
// A command that changes a session's status goes through [apply], which checks
// the move against the transition table, writes the result and records the
// move. A command that replaces the whole handoff (a new session, a reset to
// blank) goes through [replace], which records the move it makes. An edit that
// leaves the status alone goes through [rewrite], which refuses to change it.
// Nothing else in `lib/` writes the handoff; `handoff_store_test.dart` fails
// when something does.

import '../io/file_io.dart';
import '../logging/logger.dart';
import '../templates/handoff_template.dart';
import 'handoff_event.dart';
import 'md_io.dart';
import 'session_state.dart';

class HandoffStore {
  const HandoffStore({
    required this.io,
    required this.handoffFile,
    required this.logger,
    required this.command,
  });

  final FileIO io;

  /// Path of the handoff this store writes.
  final String handoffFile;

  final SessionLogger logger;

  /// The command making the moves, as the logs name it.
  final String command;

  /// Applies [event] to [content] through the transition table, writes the
  /// result and records the move. Throws when the table has no such move, and
  /// writes nothing. Returns what was written.
  String apply(String content, HandoffEvent event) {
    final updated = applyHandoffEvent(
      content,
      event,
      onTransition: (transition) =>
          logger.logTransition(command: command, transition: transition),
    );
    io.write(handoffFile, updated);
    return updated;
  }

  /// Writes [content], which must carry the status already on disk: an edit of
  /// a section, a timestamp. A different status is a move and goes through
  /// [apply] or [replace].
  void rewrite(String content) {
    final onDisk = readHandoffStatus(io.read(handoffFile));
    final incoming = readHandoffStatus(content);
    if (onDisk != incoming) {
      throw StateError(
        'rewrite changed the status from ${onDisk.value} to ${incoming.value}; '
        'a status change goes through apply or replace',
      );
    }
    io.write(handoffFile, content);
  }

  /// Replaces the whole handoff with [content], recording [event] from [from].
  /// Not enforced: starting over a live handoff, a reset and a roll-over are
  /// allowed from any status, so a move the table lacks is logged as rejected,
  /// not thrown.
  void replace(
    String content, {
    required HandoffStatus from,
    required HandoffEvent event,
  }) {
    io.write(handoffFile, content);
    logger.logHandoffMove(command: command, from: from, event: event);
  }

  /// Writes the blank handoff without recording a move, for a transaction that
  /// records its own (`closeSession` in kill).
  static void writeBlank(FileIO io, String handoffFile) =>
      io.write(handoffFile, blankHandoff);
}
