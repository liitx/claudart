// invalid_handoff_transition_exception.dart — a command asked the handoff
// state machine for a move docs/design.md's delta table does not contain.
//
// Thrown where HandoffStatus.after returns null. One class per FailureType,
// matching the existing convention (see pipeline_step_exception.dart).

import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';
import 'handoff_event.dart';
import 'session_state.dart';

class InvalidHandoffTransitionException extends ClaudartException {
  InvalidHandoffTransitionException(this.from, this.event)
      : super(
          FailureType.invalidHandoffTransition,
          context: {'from': from.value, 'event': event.name},
        );

  /// The status the handoff was in.
  final HandoffStatus from;

  /// The event the command tried to apply.
  final HandoffEvent event;

  @override
  String toString() =>
      'Handoff status "${from.value}" does not allow "${event.name}".';
}
