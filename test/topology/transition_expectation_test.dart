// Where every legal move lands, written out from docs/design.md and not read
// from the code. The generated docs only say the table did not change since
// they were made; the size pin and the graph proofs say how many cells are
// legal and how they connect. Nothing else says that a legal move lands on the
// status the spec names, so a table that sent `flowConstructed` to
// `readyForDebug` would pass them all (found by the proof audit: 125 of 896
// single-cell faults were caught by nothing but the generated docs).
//
// Statuses are in the spec's words: "any persisted state" is the six statuses
// that are written to disk, never `noHandoff` or `unknown`.

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

const _persisted = {
  HandoffStatus.suggestInvestigating,
  HandoffStatus.readyForSuggest,
  HandoffStatus.readyForDebug,
  HandoffStatus.debugInProgress,
  HandoffStatus.debugComplete,
  HandoffStatus.needsSuggest,
};

/// For each event, the statuses it is legal from and the status each lands on.
/// A cell not named here is rejected.
final Map<HandoffEvent, Map<HandoffStatus, HandoffStatus>> _landings = {
  // `claudart setup` starts a session from nothing.
  HandoffEvent.setup: {
    HandoffStatus.noHandoff: HandoffStatus.suggestInvestigating,
  },
  // `claudart flow` writes the handoff itself, past the investigation.
  HandoffEvent.flowConstructed: {
    HandoffStatus.noHandoff: HandoffStatus.readyForSuggest,
  },
  // `/save` with the root cause unconfirmed keeps the status.
  HandoffEvent.saveUnconfirmed: {
    HandoffStatus.suggestInvestigating: HandoffStatus.suggestInvestigating,
    HandoffStatus.debugInProgress: HandoffStatus.debugInProgress,
  },
  // `/save` with the root cause confirmed and more exploring expected.
  HandoffEvent.saveConfirmedExploring: {
    HandoffStatus.suggestInvestigating: HandoffStatus.readyForSuggest,
  },
  // `/save` with the root cause confirmed and ready to implement.
  HandoffEvent.saveConfirmedReady: {
    HandoffStatus.suggestInvestigating: HandoffStatus.readyForDebug,
    HandoffStatus.readyForSuggest: HandoffStatus.readyForDebug,
    HandoffStatus.readyForDebug: HandoffStatus.readyForDebug,
    HandoffStatus.debugInProgress: HandoffStatus.readyForDebug,
    HandoffStatus.needsSuggest: HandoffStatus.readyForDebug,
  },
  // `/debug` begins.
  HandoffEvent.debugStarted: {
    HandoffStatus.readyForDebug: HandoffStatus.debugInProgress,
  },
  // Debug hits a question suggest must resolve.
  HandoffEvent.debugBlocked: {
    HandoffStatus.debugInProgress: HandoffStatus.needsSuggest,
  },
  // `/suggest` answers debug's question.
  HandoffEvent.suggestResumed: {
    HandoffStatus.needsSuggest: HandoffStatus.suggestInvestigating,
  },
  // `/debug` applies its plan.
  HandoffEvent.fixApplied: {
    HandoffStatus.readyForDebug: HandoffStatus.debugComplete,
    HandoffStatus.debugInProgress: HandoffStatus.debugComplete,
  },
  // `claudart rotate` with a pending issue starts the next session.
  HandoffEvent.rotated: {
    HandoffStatus.suggestInvestigating: HandoffStatus.suggestInvestigating,
    HandoffStatus.readyForDebug: HandoffStatus.suggestInvestigating,
    HandoffStatus.debugInProgress: HandoffStatus.suggestInvestigating,
  },
  // `claudart rotate` with no pending issue leaves no session.
  HandoffEvent.rotatedEmpty: {
    HandoffStatus.suggestInvestigating: HandoffStatus.noHandoff,
    HandoffStatus.readyForDebug: HandoffStatus.noHandoff,
    HandoffStatus.debugInProgress: HandoffStatus.noHandoff,
  },
  // `claudart teardown` where the knowledge transfer is complete.
  HandoffEvent.tornDown: {
    HandoffStatus.readyForSuggest: HandoffStatus.noHandoff,
    HandoffStatus.readyForDebug: HandoffStatus.noHandoff,
    HandoffStatus.debugInProgress: HandoffStatus.noHandoff,
    HandoffStatus.debugComplete: HandoffStatus.noHandoff,
  },
  // `claudart teardown` on an unresolved session: any persisted state.
  HandoffEvent.reminderSaved: {
    for (final status in _persisted) status: HandoffStatus.noHandoff,
  },
  // `claudart kill`: any persisted state.
  HandoffEvent.killed: {
    for (final status in _persisted) status: HandoffStatus.noHandoff,
  },
};

void main() {
  test('the expectation names an event for every event', () {
    expect(_landings.keys.toSet(), HandoffEvent.values.toSet());
  });

  test('the expectation names 37 legal moves, as the spec lists them', () {
    expect(
      _landings.values.fold<int>(0, (count, cells) => count + cells.length),
      37,
    );
  });

  group('where a move lands', () {
    for (final event in HandoffEvent.values) {
      for (final status in HandoffStatus.values) {
        final expected = _landings[event]![status];
        test(
          '${status.name} x ${event.name} '
          '${expected == null ? 'is rejected' : 'lands on ${expected.name}'}',
          () => expect(status.after(event), expected),
        );
      }
    }
  });
}
