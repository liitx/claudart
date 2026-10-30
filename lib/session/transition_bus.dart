// transition_bus.dart — the stream every status change is published on
//
// Two kinds of subscriber, on purpose. A record runs inline while the move is
// published: it is a file append, and a process that exits right after a move
// must not lose it. A reaction runs later, one after another in the order the
// moves were published, and may return an event for the writer to apply; that
// event's move is queued behind the ones already published. A subscriber that
// throws is reported and does not stop the others or the publisher. [drain]
// completes when nothing is pending, so a command awaits it before it returns.

import 'dart:async';

import 'handoff_event.dart';
import 'handoff_transition.dart';

/// A subscriber that threw, with the move it was handling.
class HandoffListenerFailure {
  const HandoffListenerFailure({
    required this.listener,
    required this.transition,
    required this.error,
  });

  final String listener;
  final HandoffTransition transition;
  final Object error;
}

class HandoffTransitionBus {
  HandoffTransitionBus({required this.applyNext, required this.onFailure});

  /// Applies an event a reaction returned and gives the move it made.
  final Future<HandoffTransition> Function(HandoffEvent event) applyNext;

  /// Hears every subscriber that throws.
  final void Function(HandoffListenerFailure failure) onFailure;

  final _controller = StreamController<HandoffTransition>.broadcast();
  final _records = <(String, void Function(HandoffTransition))>[];
  final _reactions =
      <(String, Future<HandoffEvent?> Function(HandoffTransition))>[];
  Future<void> _tail = Future<void>.value();
  var _pending = 0;

  /// Every published move, for observers that only watch.
  Stream<HandoffTransition> get transitions => _controller.stream;

  /// Adds a subscriber that runs inline when a move is published.
  void record(String name, void Function(HandoffTransition move) listener) =>
      _records.add((name, listener));

  /// Adds a subscriber that runs after the move, in publication order, and may
  /// return the next event.
  void react(
    String name,
    Future<HandoffEvent?> Function(HandoffTransition move) listener,
  ) =>
      _reactions.add((name, listener));

  /// Publishes [move]: records run now, reactions are queued.
  void publish(HandoffTransition move) {
    for (final (name, listener) in _records) {
      try {
        listener(move);
      } catch (error) {
        onFailure(
          HandoffListenerFailure(listener: name, transition: move, error: error),
        );
      }
    }
    _controller.add(move);
    if (_reactions.isEmpty) return;
    _pending++;
    _tail = _tail.then((_) => _dispatch(move));
  }

  Future<void> _dispatch(HandoffTransition move) async {
    try {
      for (final (name, listener) in _reactions) {
        try {
          final next = await listener(move);
          if (next != null) publish(await applyNext(next));
        } catch (error) {
          onFailure(
            HandoffListenerFailure(
              listener: name,
              transition: move,
              error: error,
            ),
          );
        }
      }
    } finally {
      _pending--;
    }
  }

  /// Completes when every published move, and every move a reaction caused,
  /// has been handled.
  Future<void> drain() async {
    while (_pending > 0) {
      await _tail;
    }
  }
}
