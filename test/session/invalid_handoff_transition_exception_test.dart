import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/fault_class.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

void main() {
  group('InvalidHandoffTransitionException', () {
    final e = InvalidHandoffTransitionException(
      HandoffStatus.debugComplete,
      HandoffEvent.debugStarted,
    );

    test('carries invalidHandoffTransition and its programmerFault class', () {
      expect(e.failureType, FailureType.invalidHandoffTransition);
      expect(e.faultClass, FaultClass.programmerFault);
    });

    test('keeps the offending status and event as typed fields', () {
      expect(e.from, HandoffStatus.debugComplete);
      expect(e.event, HandoffEvent.debugStarted);
    });

    test('toString names the status by its handoff.md value and the event', () {
      expect(
        e.toString(),
        'Handoff status "debug-complete" does not allow "debugStarted".',
      );
    });
  });
}
