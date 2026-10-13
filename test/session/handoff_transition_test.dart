import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../helpers/variant_topology.dart';

typedef _Move = (HandoffStatus, HandoffEvent, HandoffStatus);

// Independent literal table of every legal move: docs/design.md's delta table
// plus the three rows marked "extension" there. Anything not listed is
// rejected. Not derived from HandoffStatus.after, so it can catch a wrong one.
const _legal = <_Move>{
  (
    HandoffStatus.noHandoff,
    HandoffEvent.setup,
    HandoffStatus.suggestInvestigating,
  ),
  (
    HandoffStatus.suggestInvestigating,
    HandoffEvent.saveUnconfirmed,
    HandoffStatus.suggestInvestigating,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.saveUnconfirmed,
    HandoffStatus.debugInProgress,
  ),
  (
    HandoffStatus.suggestInvestigating,
    HandoffEvent.saveConfirmedExploring,
    HandoffStatus.readyForSuggest,
  ),
  (
    HandoffStatus.suggestInvestigating,
    HandoffEvent.saveConfirmedReady,
    HandoffStatus.readyForDebug,
  ),
  (
    HandoffStatus.readyForSuggest,
    HandoffEvent.saveConfirmedReady,
    HandoffStatus.readyForDebug,
  ),
  // extension: suggest re-run overwrites a locked or blocked handoff
  (
    HandoffStatus.readyForDebug,
    HandoffEvent.saveConfirmedReady,
    HandoffStatus.readyForDebug,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.saveConfirmedReady,
    HandoffStatus.readyForDebug,
  ),
  (
    HandoffStatus.needsSuggest,
    HandoffEvent.saveConfirmedReady,
    HandoffStatus.readyForDebug,
  ),
  (
    HandoffStatus.readyForDebug,
    HandoffEvent.debugStarted,
    HandoffStatus.debugInProgress,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.debugBlocked,
    HandoffStatus.needsSuggest,
  ),
  (
    HandoffStatus.needsSuggest,
    HandoffEvent.suggestResumed,
    HandoffStatus.suggestInvestigating,
  ),
  // extension: runDebug applies the plan and marks it complete in one step
  (
    HandoffStatus.readyForDebug,
    HandoffEvent.fixApplied,
    HandoffStatus.debugComplete,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.fixApplied,
    HandoffStatus.debugComplete,
  ),
  (
    HandoffStatus.suggestInvestigating,
    HandoffEvent.rotated,
    HandoffStatus.suggestInvestigating,
  ),
  (
    HandoffStatus.readyForDebug,
    HandoffEvent.rotated,
    HandoffStatus.suggestInvestigating,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.rotated,
    HandoffStatus.suggestInvestigating,
  ),
  (
    HandoffStatus.debugComplete,
    HandoffEvent.tornDown,
    HandoffStatus.noHandoff,
  ),
  // kill: any persisted state, handoff erased
  (
    HandoffStatus.suggestInvestigating,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
  (
    HandoffStatus.readyForSuggest,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
  (
    HandoffStatus.readyForDebug,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
  (
    HandoffStatus.debugInProgress,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
  (
    HandoffStatus.debugComplete,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
  (
    HandoffStatus.needsSuggest,
    HandoffEvent.killed,
    HandoffStatus.noHandoff,
  ),
};

HandoffStatus? _expected(HandoffStatus from, HandoffEvent event) {
  for (final (legalFrom, legalEvent, to) in _legal) {
    if (legalFrom == from && legalEvent == event) return to;
  }
  return null;
}

void main() {
  group('HandoffStatus.after — every (state, event) pair', () {
    for (final from in HandoffStatus.values) {
      for (final event in HandoffEvent.values) {
        final to = _expected(from, event);
        test('${from.name} --${event.name}--> ${to?.name ?? 'rejected'}', () {
          expect(from.after(event), to);
        });
      }
    }
  });

  group('HandoffStatus.after — properties', () {
    Set<HandoffStatus> reachableFrom(HandoffStatus start) {
      final seen = {start};
      final queue = [start];
      while (queue.isNotEmpty) {
        final status = queue.removeLast();
        for (final event in HandoffEvent.values) {
          final next = status.after(event);
          if (next != null && seen.add(next)) queue.add(next);
        }
      }
      return seen;
    }

    test('every persisted status is reachable from noHandoff', () {
      final persisted = HandoffStatus.values.where((s) => s.isPersisted);
      expect(
        reachableFrom(HandoffStatus.noHandoff),
        {HandoffStatus.noHandoff, ...persisted},
      );
    });

    test('the display-only unknown status is never entered', () {
      expect(
        reachableFrom(HandoffStatus.noHandoff),
        isNot(contains(HandoffStatus.unknown)),
      );
    });

    test('every persisted status has a way out (no dead ends)', () {
      final stuck = HandoffStatus.values
          .where((s) => s.isPersisted)
          .where((s) => HandoffEvent.values.every((e) => s.after(e) == null));
      expect(stuck, isEmpty);
    });

    test('topology: the legal next statuses per state, from the code', () {
      final next = topologyOf(
        HandoffStatus.values,
        (s) => {
          for (final e in HandoffEvent.values)
            if (s.after(e) != null) e: s.after(e),
        },
      );
      expect(
          next[HandoffStatus.readyForDebug]!.keys,
          containsAll([
            HandoffEvent.debugStarted,
            HandoffEvent.fixApplied,
            HandoffEvent.killed,
          ]));
    });
  });
}
