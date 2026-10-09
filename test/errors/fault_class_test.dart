import 'package:test/test.dart';
import 'package:claudart/errors/fault_class.dart';

void main() {
  group('FaultClass.severity', () {
    test('environmentFault is error', () {
      expect(FaultClass.environmentFault.severity, FaultSeverity.error);
    });
    test('configFault is error', () {
      expect(FaultClass.configFault.severity, FaultSeverity.error);
    });
    test('externalServiceFault is error', () {
      expect(FaultClass.externalServiceFault.severity, FaultSeverity.error);
    });
    test('transientFault is warn', () {
      expect(FaultClass.transientFault.severity, FaultSeverity.warn);
    });
    test('programmerFault is fatal', () {
      expect(FaultClass.programmerFault.severity, FaultSeverity.fatal);
    });
  });

  group('FaultClass.retryable', () {
    test('transientFault is retryable', () {
      expect(FaultClass.transientFault.retryable, isTrue);
    });
    test('environmentFault is not retryable', () {
      expect(FaultClass.environmentFault.retryable, isFalse);
    });
    test('configFault is not retryable', () {
      expect(FaultClass.configFault.retryable, isFalse);
    });
    test('externalServiceFault is not retryable', () {
      expect(FaultClass.externalServiceFault.retryable, isFalse);
    });
    test('programmerFault is not retryable', () {
      expect(FaultClass.programmerFault.retryable, isFalse);
    });
  });

  group('FaultSeverity.blocking', () {
    test('fatal blocks', () => expect(FaultSeverity.fatal.blocking, isTrue));
    test('error blocks', () => expect(FaultSeverity.error.blocking, isTrue));
    test('warn does not block', () => expect(FaultSeverity.warn.blocking, isFalse));
    test('info does not block', () => expect(FaultSeverity.info.blocking, isFalse));
  });

  group('FaultClass.label', () {
    for (final fc in FaultClass.values) {
      test('${fc.name} has a non-empty label', () {
        expect(fc.label, isNotEmpty);
      });
    }
  });
}
