import 'package:test/test.dart';
import 'package:claudart/errors/error_type.dart';
import 'package:claudart/errors/fault_class.dart';

void main() {
  group('ErrorType.faultClass', () {
    test('scan rolls up to environmentFault', () {
      expect(ErrorType.scan.faultClass, FaultClass.environmentFault);
    });
    test('archive rolls up to environmentFault', () {
      expect(ErrorType.archive.faultClass, FaultClass.environmentFault);
    });
    test('session rolls up to environmentFault', () {
      expect(ErrorType.session.faultClass, FaultClass.environmentFault);
    });
    test('workspace rolls up to environmentFault', () {
      expect(ErrorType.workspace.faultClass, FaultClass.environmentFault);
    });
  });

  group('ErrorType.label', () {
    for (final et in ErrorType.values) {
      test('${et.name} has a non-empty label', () {
        expect(et.label, isNotEmpty);
      });
    }
  });
}
