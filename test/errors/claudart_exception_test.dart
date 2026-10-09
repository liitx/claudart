import 'package:test/test.dart';
import 'package:claudart/errors/claudart_exception.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/fault_class.dart';

void main() {
  group('ClaudartException', () {
    test('errorType/faultClass walk the chain through failureType', () {
      final e = ClaudartException(FailureType.scanThresholdExceeded);
      expect(e.errorType.name, 'scan');
      expect(e.faultClass, FaultClass.environmentFault);
    });

    test('faultClass uses effectiveFaultClass, not the raw subsystem default', () {
      final e = ClaudartException(FailureType.workspaceLocked);
      expect(e.faultClass, FaultClass.transientFault);
    });

    test('toString includes the failure type name', () {
      final e = ClaudartException(FailureType.sessionCloseFailed);
      expect(e.toString(), contains('sessionCloseFailed'));
    });

    test('toString includes context entries when present', () {
      final e = ClaudartException(
        FailureType.workspaceLocked,
        context: {'workspacePath': '/ws/proj'},
      );
      expect(e.toString(), contains('workspacePath=/ws/proj'));
    });

    test('toString includes stderr when present', () {
      final e = ClaudartException(FailureType.archiveIndexCorrupt, stderr: 'boom');
      expect(e.toString(), contains('boom'));
    });

    test('toString omits context/stderr sections when absent', () {
      final e = ClaudartException(FailureType.scanThresholdExceeded);
      final s = e.toString();
      expect(s, isNot(contains('stderr')));
    });
  });
}
