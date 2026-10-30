// The static proofs of the listener design (docs/methodical_refactor.md,
// stage 3), written before the code: totality, safety, termination. They are
// checked over every cell of the transition table, not over examples.

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_listeners.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

/// Every legal cell of the transition table as the transition it makes.
List<HandoffTransition> legalCells() => [
      for (final from in HandoffStatus.values)
        for (final event in HandoffEvent.values)
          if (from.after(event) != null)
            HandoffTransition(from: from, event: event, to: from.after(event)!),
    ];

/// The (cell, kind, event) triples where a listener of [kind] may emit an event
/// that is not legal from the status the cell lands in.
List<String> unsafeEmissions({
  required List<HandoffListenerKind> Function(HandoffTransition) listeners,
  required Set<HandoffEvent> Function(HandoffListenerKind) emits,
}) =>
    [
      for (final cell in legalCells())
        for (final kind in listeners(cell))
          for (final event in emits(kind))
            if (cell.to.after(event) == null)
              '${cell.from.name} --${cell.event.name}--> ${cell.to.name}: '
                  '${kind.name} emits ${event.name}',
    ];

/// Whether the relation event -> events has a cycle.
bool hasCycle(Map<HandoffEvent, Set<HandoffEvent>> relation) {
  final state = <HandoffEvent, int>{}; // 1 = on the path, 2 = done
  bool visit(HandoffEvent event) {
    if (state[event] == 1) return true;
    if (state[event] == 2) return false;
    state[event] = 1;
    for (final next in relation[event] ?? const <HandoffEvent>{}) {
      if (visit(next)) return true;
    }
    state[event] = 2;
    return false;
  }

  return relation.keys.any(visit);
}

/// The relation the listeners define: an event may be followed by whatever a
/// listener of a cell that event makes may emit.
Map<HandoffEvent, Set<HandoffEvent>> emitRelation() {
  final relation = <HandoffEvent, Set<HandoffEvent>>{};
  for (final cell in legalCells()) {
    for (final kind in listenersFor(cell)) {
      relation.putIfAbsent(cell.event, () => {}).addAll(kind.mayEmit);
    }
  }
  return relation;
}

void main() {
  group('totality', () {
    for (final cell in legalCells()) {
      test('${cell.from.name} --${cell.event.name}--> ${cell.to.name} is '
          'decided and recorded', () {
        expect(listenersFor(cell), contains(HandoffListenerKind.recordTransition));
      });
    }

    test('a move is listed once per kind', () {
      for (final cell in legalCells()) {
        final kinds = listenersFor(cell);
        expect(kinds.toSet().length, kinds.length, reason: '$cell');
      }
    });
  });

  group('totality over events', () {
    test('every event is decided, including those no status makes yet', () {
      for (final event in HandoffEvent.values) {
        for (final to in HandoffStatus.values) {
          final kinds = listenersFor(
            HandoffTransition(from: HandoffStatus.unknown, event: event, to: to),
          );
          expect(kinds, contains(HandoffListenerKind.recordTransition),
              reason: '${event.name} -> ${to.name}');
        }
      }
    });

    test('only a fix landing on a finished fix calls for a teardown', () {
      final calling = [
        for (final cell in legalCells())
          if (listenersFor(cell)
              .contains(HandoffListenerKind.teardownWhenConverged))
            cell,
      ];
      expect(
        calling.map((cell) => cell.event).toSet(),
        {HandoffEvent.fixApplied},
      );
      expect(
        calling.map((cell) => cell.to).toSet(),
        {HandoffStatus.debugComplete},
      );
    });
  });

  group('safety', () {
    test('no listener may emit an event the landing status forbids', () {
      expect(
        unsafeEmissions(
          listeners: listenersFor,
          emits: (kind) => kind.mayEmit,
        ),
        isEmpty,
      );
    });

    test('the check finds an emission the table forbids', () {
      final found = unsafeEmissions(
        listeners: (_) => [HandoffListenerKind.recordTransition],
        emits: (_) => {HandoffEvent.debugStarted},
      );
      expect(found, isNotEmpty);
    });
  });

  group('termination', () {
    test('the events listeners may emit form no cycle', () {
      expect(hasCycle(emitRelation()), isFalse);
    });

    test('the check finds a cycle', () {
      expect(
        hasCycle({
          HandoffEvent.setup: {HandoffEvent.killed},
          HandoffEvent.killed: {HandoffEvent.setup},
        }),
        isTrue,
      );
    });

    test('the check finds a self-loop', () {
      expect(
        hasCycle({HandoffEvent.setup: {HandoffEvent.setup}}),
        isTrue,
      );
    });

    test('a chain is at most as long as there are events', () {
      // Acyclic over N events means no path has more than N hops.
      expect(HandoffEvent.values.length, 13);
    });
  });
}
