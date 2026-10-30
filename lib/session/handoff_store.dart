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
import 'handoff_listeners.dart';
import 'handoff_transition.dart';
import 'invalid_handoff_transition_exception.dart';
import 'transition_bus.dart';
import 'md_io.dart';
import 'session_state.dart';

class HandoffStore {
  HandoffStore({
    required this.io,
    required this.handoffFile,
    required this.logger,
    required this.command,
  }) {
    bus = HandoffTransitionBus(
      applyNext: (event) async => _applyReturned(event),
      onFailure: (failure) =>
          logger.logListenerFailure(command: command, failure: failure),
    )..record(
        HandoffListenerKind.recordTransition.name,
        (move) => logger.logTransition(command: command, transition: move),
      );
  }

  final FileIO io;

  /// Path of the handoff this store writes.
  final String handoffFile;

  final SessionLogger logger;

  /// The command making the moves, as the logs name it.
  final String command;

  /// Every move this store makes is published here. The record of the move is
  /// a subscriber that runs inline; reactions are added with [react].
  late final HandoffTransitionBus bus;

  /// Adds a reaction to every move this store makes. It may return an event;
  /// the store applies it, so the next hop is a move on the same bus and in
  /// the same log.
  void react(
    String name,
    Future<HandoffEvent?> Function(HandoffTransition move) listener,
  ) =>
      bus.react(name, listener);

  /// Completes when every reaction has finished. A command that added a
  /// reaction awaits this before it returns.
  Future<void> drain() => bus.drain();

  /// Applies [event] to [content] through the transition table, writes the
  /// result and records the move. Throws when the table has no such move, and
  /// writes nothing. Returns what was written.
  String apply(String content, HandoffEvent event) {
    final written = _write(content, event);
    bus.publish(written.move);
    return written.content;
  }

  /// Applies [content]'s next move on disk without publishing it.
  ({String content, HandoffTransition move}) _write(
    String content,
    HandoffEvent event,
  ) {
    late HandoffTransition move;
    final updated = applyHandoffEvent(
      content,
      event,
      onTransition: (transition) => move = transition,
    );
    io.write(handoffFile, updated);
    return (content: updated, move: move);
  }

  /// Applies an event a reaction returned. The bus publishes the move this
  /// gives, so it is not published here. A move to a status that is never
  /// written to disk (`noHandoff`) is made by writing the blank handoff.
  HandoffTransition _applyReturned(HandoffEvent event) {
    final content = io.read(handoffFile);
    final from = readHandoffStatus(content);
    final to = from.after(event);
    if (to == null) throw InvalidHandoffTransitionException(from, event);
    if (!to.isPersisted) {
      io.write(handoffFile, blankHandoff);
      return HandoffTransition(from: from, event: event, to: to);
    }
    return _write(content, event).move;
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
    final to = from.after(event);
    if (to == null) {
      logger.logHandoffMove(command: command, from: from, event: event);
      return;
    }
    bus.publish(HandoffTransition(from: from, event: event, to: to));
  }

  /// Writes the blank handoff without recording a move, for a transaction that
  /// records its own (`closeSession` in kill).
  static void writeBlank(FileIO io, String handoffFile) =>
      io.write(handoffFile, blankHandoff);
}
