// handoff_listeners.dart — which reactions a status change calls for
//
// Decided per landing status by an exhaustive switch with no default arm, so a
// new status fails to compile until someone decides what follows it. A reaction
// that must start the next sequence names the events it may return in
// [HandoffListenerKind.mayEmit]; `handoff_listeners_test.dart` proves every
// such event is legal where it lands and that the events listeners can chain
// form no cycle.

import 'handoff_event.dart';
import 'handoff_transition.dart';
import 'session_state.dart';

/// A reaction to a status change.
enum HandoffListenerKind {
  /// Writes the move to `transitions.jsonl`. Runs inline, so a process that
  /// exits right after a move has still recorded it.
  recordTransition(mayEmit: {}),

  /// Closes a verified, converged session with `teardown`. Declared and
  /// proven, not yet attached: only headless and flow runs may attach it.
  teardownWhenConverged(mayEmit: {HandoffEvent.tornDown});

  const HandoffListenerKind({required this.mayEmit});

  /// The events a listener of this kind may return for the writer to apply.
  final Set<HandoffEvent> mayEmit;
}

/// The reactions [transition] calls for. Exhaustive over the events, so a new
/// event fails to compile until someone decides what follows it; the landing
/// status matters only where a reaction depends on it.
List<HandoffListenerKind> listenersFor(HandoffTransition transition) =>
    switch (transition.event) {
      HandoffEvent.fixApplied => switch (transition.to) {
          HandoffStatus.debugComplete => const [
              HandoffListenerKind.recordTransition,
              HandoffListenerKind.teardownWhenConverged,
            ],
          HandoffStatus.suggestInvestigating ||
          HandoffStatus.readyForSuggest ||
          HandoffStatus.readyForDebug ||
          HandoffStatus.debugInProgress ||
          HandoffStatus.needsSuggest ||
          HandoffStatus.noHandoff ||
          HandoffStatus.unknown =>
            const [HandoffListenerKind.recordTransition],
        },
      HandoffEvent.setup ||
      HandoffEvent.saveUnconfirmed ||
      HandoffEvent.saveConfirmedExploring ||
      HandoffEvent.saveConfirmedReady ||
      HandoffEvent.debugStarted ||
      HandoffEvent.debugBlocked ||
      HandoffEvent.suggestResumed ||
      HandoffEvent.rotated ||
      HandoffEvent.rotatedEmpty ||
      HandoffEvent.tornDown ||
      HandoffEvent.reminderSaved ||
      HandoffEvent.killed =>
        const [HandoffListenerKind.recordTransition],
    };
