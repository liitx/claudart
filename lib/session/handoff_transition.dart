// handoff_transition.dart — one applied status change, as typed data.
//
// What a listener sees when a command moves a handoff: the status it was in,
// the event it applied, and the status it landed in. Logged per command
// (SessionLogger.logTransition) so which enum was passed where is on record.

import 'handoff_event.dart';
import 'session_state.dart';

/// The keys of a transition's JSON; the names are the keys.
enum HandoffTransitionField { from, event, to }

class HandoffTransition {
  const HandoffTransition({
    required this.from,
    required this.event,
    required this.to,
  });

  final HandoffStatus from;
  final HandoffEvent event;
  final HandoffStatus to;

  Map<String, Object?> toJson() => {
        HandoffTransitionField.from.name: from.name,
        HandoffTransitionField.event.name: event.name,
        HandoffTransitionField.to.name: to.name,
      };

  @override
  bool operator ==(Object other) =>
      other is HandoffTransition &&
      other.from == from &&
      other.event == event &&
      other.to == to;

  @override
  int get hashCode => Object.hash(from, event, to);
}
