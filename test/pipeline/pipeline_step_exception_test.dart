import 'package:test/test.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/fault_class.dart';
import 'package:claudart/pipeline/pipeline_step_exception.dart';

void main() {
  group('ProviderNotConfiguredException', () {
    test('carries providerNotConfigured and its configFault override', () {
      final e = ProviderNotConfiguredException();
      expect(e.failureType, FailureType.providerNotConfigured);
      expect(e.faultClass, FaultClass.configFault);
    });

    test('toString names the checked sources and the diagnose command', () {
      final e = ProviderNotConfiguredException();
      expect(
        e.toString(),
        'No agent provider configured (checked ANTHROPIC_API_KEY, Bedrock '
        'env vars, and ~/.claude/settings.json). Run `claudart doctor` to diagnose.',
      );
    });
  });

  group('StepTimedOutException', () {
    test('carries stepTimedOut and its transientFault override', () {
      final e = StepTimedOutException(const Duration(seconds: 30));
      expect(e.failureType, FailureType.stepTimedOut);
      expect(e.faultClass, FaultClass.transientFault);
    });

    test('toString pluralizes "seconds" correctly', () {
      expect(StepTimedOutException(const Duration(seconds: 1)).toString(), contains('1 second'));
      expect(StepTimedOutException(const Duration(seconds: 1)).toString(),
          isNot(contains('1 seconds')));
      expect(StepTimedOutException(const Duration(seconds: 5)).toString(), contains('5 seconds'));
    });

    test('toString names the config key to raise or disable', () {
      expect(
        StepTimedOutException(const Duration(seconds: 5)).toString(),
        'claude step timed out after 5 seconds and was killed. '
        'Raise or disable (0) "stepTimeoutMinutes" in the workspace config.json.',
      );
    });
  });

  group('StepExitedNonZeroException', () {
    test('carries stepExitedNonzero and its subsystem default faultClass', () {
      final e = StepExitedNonZeroException(3);
      expect(e.failureType, FailureType.stepExitedNonzero);
      expect(e.faultClass, FaultClass.externalServiceFault);
    });

    test('toString includes the exit code and stderr when present', () {
      final e = StepExitedNonZeroException(3, stderr: 'boom');
      expect(e.toString(), equals('claude exited 3: boom'));
    });

    test('toString omits the stderr suffix when absent', () {
      final e = StepExitedNonZeroException(1);
      expect(e.toString(), equals('claude exited 1'));
    });
  });

  group('StepProducedNoResultException', () {
    test('carries stepProducedNoResult and its subsystem default faultClass', () {
      final e = StepProducedNoResultException();
      expect(e.failureType, FailureType.stepProducedNoResult);
      expect(e.faultClass, FaultClass.externalServiceFault);
    });

    test('toString names the real condition', () {
      expect(StepProducedNoResultException().toString(), equals('claude produced no result line'));
    });
  });
}
