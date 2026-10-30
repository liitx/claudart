// The runtime proofs of the listener design, written before the code: order,
// drain, isolation, and that the record is never lost to asynchrony.

import 'dart:async';

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/session/transition_bus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

HandoffTransition _move(HandoffEvent event) => HandoffTransition(
      from: HandoffStatus.readyForDebug,
      event: event,
      to: HandoffStatus.debugInProgress,
    );

void main() {
  late List<HandoffListenerFailure> failures;

  HandoffTransitionBus busOf({
    Future<HandoffTransition> Function(HandoffEvent event)? applyNext,
  }) =>
      HandoffTransitionBus(
        applyNext: applyNext ?? (event) async => _move(event),
        onFailure: failures.add,
      );

  setUp(() => failures = []);

  group('asynchrony', () {
    test('a reaction does not run while the move is being published', () async {
      final bus = busOf();
      final seen = <HandoffEvent>[];
      bus.react('reaction', (move) async {
        seen.add(move.event);
        return null;
      });
      bus.publish(_move(HandoffEvent.debugStarted));
      expect(seen, isEmpty);
      await bus.drain();
      expect(seen, [HandoffEvent.debugStarted]);
    });

    test('a record runs while the move is being published', () {
      final bus = busOf();
      final seen = <HandoffEvent>[];
      bus.record('record', (move) => seen.add(move.event));
      bus.publish(_move(HandoffEvent.debugStarted));
      expect(seen, [HandoffEvent.debugStarted]);
    });
  });

  group('observers', () {
    test('the transitions stream shows every published move, later', () {
      fakeAsync((async) {
        final bus = busOf();
        final seen = <HandoffEvent>[];
        bus.transitions.listen((move) => seen.add(move.event));
        bus
          ..publish(_move(HandoffEvent.debugStarted))
          ..publish(_move(HandoffEvent.killed));
        expect(seen, isEmpty);
        async.flushMicrotasks();
        expect(seen, [HandoffEvent.debugStarted, HandoffEvent.killed]);
      });
    });
  });

  group('order', () {
    test('reactions see moves in the order they were published', () {
      fakeAsync((async) {
        final bus = busOf();
        final seen = <HandoffEvent>[];
        bus.react('slow first', (move) async {
          if (move.event == HandoffEvent.debugStarted) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          seen.add(move.event);
          return null;
        });
        bus
          ..publish(_move(HandoffEvent.debugStarted))
          ..publish(_move(HandoffEvent.fixApplied))
          ..publish(_move(HandoffEvent.killed));
        async.elapse(const Duration(milliseconds: 29));
        expect(seen, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(seen, [
          HandoffEvent.debugStarted,
          HandoffEvent.fixApplied,
          HandoffEvent.killed,
        ]);
      });
    });

    test('an event a reaction returns is queued behind moves already published',
        () async {
      final bus = busOf();
      final seen = <HandoffEvent>[];
      bus.react('chain', (move) async {
        seen.add(move.event);
        return move.event == HandoffEvent.debugStarted
            ? HandoffEvent.fixApplied
            : null;
      });
      bus
        ..publish(_move(HandoffEvent.debugStarted))
        ..publish(_move(HandoffEvent.killed));
      await bus.drain();
      expect(seen, [
        HandoffEvent.debugStarted,
        HandoffEvent.killed,
        HandoffEvent.fixApplied,
      ]);
    });
  });

  group('drain', () {
    test('drain completes only when a slow reaction has finished', () {
      fakeAsync((async) {
        final bus = busOf();
        var finished = false;
        bus.react('slow', (move) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          finished = true;
          return null;
        });
        bus.publish(_move(HandoffEvent.debugStarted));
        var drained = false;
        bus.drain().then((_) => drained = true);
        async.elapse(const Duration(milliseconds: 39));
        expect(finished, isFalse);
        expect(drained, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(finished, isTrue);
        expect(drained, isTrue);
      });
    });

    test('drain waits for the moves a reaction caused', () async {
      final bus = busOf();
      var chained = false;
      bus.react('chain', (move) async {
        if (move.event == HandoffEvent.fixApplied) chained = true;
        return move.event == HandoffEvent.debugStarted
            ? HandoffEvent.fixApplied
            : null;
      });
      bus.publish(_move(HandoffEvent.debugStarted));
      await bus.drain();
      expect(chained, isTrue);
    });

    test('drain of a bus with nothing published completes', () async {
      await busOf().drain();
    });
  });

  group('isolation', () {
    test('a reaction that throws is reported and the others still run', () async {
      final bus = busOf();
      final seen = <String>[];
      bus.react('breaks', (move) async => throw StateError('boom'));
      bus.react('steady', (move) async {
        seen.add('steady');
        return null;
      });
      bus.publish(_move(HandoffEvent.debugStarted));
      await bus.drain();
      expect(seen, ['steady']);
      expect(failures, hasLength(1));
      expect(failures.single.listener, 'breaks');
      expect(failures.single.transition.event, HandoffEvent.debugStarted);
      expect(failures.single.error, isA<StateError>());
    });

    test('a record that throws is reported and the publisher is not stopped',
        () {
      final bus = busOf();
      final seen = <String>[];
      bus.record('breaks', (move) => throw StateError('boom'));
      bus.record('steady', (move) => seen.add('steady'));
      bus.publish(_move(HandoffEvent.debugStarted));
      expect(seen, ['steady']);
      expect(failures.single.listener, 'breaks');
    });

    test('a failure applying a returned event is reported, not thrown',
        () async {
      final bus = busOf(applyNext: (event) async => throw StateError('no move'));
      bus.react('chain', (move) async => HandoffEvent.fixApplied);
      bus.publish(_move(HandoffEvent.debugStarted));
      await bus.drain();
      expect(failures, hasLength(1));
      expect(failures.single.listener, 'chain');
    });
  });
}
