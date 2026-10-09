import 'package:test/test.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/error_type.dart';
import 'package:claudart/errors/fault_class.dart';

void main() {
  group('FailureType.errorType', () {
    test('scanThresholdExceeded rolls up to scan', () {
      expect(FailureType.scanThresholdExceeded.errorType, ErrorType.scan);
    });
    test('archiveIndexCorrupt rolls up to archive', () {
      expect(FailureType.archiveIndexCorrupt.errorType, ErrorType.archive);
    });
    test('sessionCloseFailed rolls up to session', () {
      expect(FailureType.sessionCloseFailed.errorType, ErrorType.session);
    });
    test('workspaceLocked rolls up to workspace', () {
      expect(FailureType.workspaceLocked.errorType, ErrorType.workspace);
    });
  });

  group('FailureType.effectiveFaultClass', () {
    test('workspaceLocked overrides to transientFault, not workspace\'s default environmentFault', () {
      expect(FailureType.workspaceLocked.faultClass, FaultClass.environmentFault);
      expect(FailureType.workspaceLocked.effectiveFaultClass, FaultClass.transientFault);
    });
    test('scanThresholdExceeded uses its subsystem default, unoverridden', () {
      expect(FailureType.scanThresholdExceeded.effectiveFaultClass, FaultClass.environmentFault);
    });
    test('archiveIndexCorrupt uses its subsystem default, unoverridden', () {
      expect(FailureType.archiveIndexCorrupt.effectiveFaultClass, FaultClass.environmentFault);
    });
    test('sessionCloseFailed uses its subsystem default, unoverridden', () {
      expect(FailureType.sessionCloseFailed.effectiveFaultClass, FaultClass.environmentFault);
    });
  });

  group('FailureType.label and suggestedAction', () {
    for (final ft in FailureType.values) {
      test('${ft.name} has a non-empty label and suggestedAction', () {
        expect(ft.label, isNotEmpty);
        expect(ft.suggestedAction, isNotEmpty);
      });
    }
  });
}
