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
    test('providerNotConfigured rolls up to pipeline', () {
      expect(FailureType.providerNotConfigured.errorType, ErrorType.pipeline);
    });
    test('stepTimedOut rolls up to pipeline', () {
      expect(FailureType.stepTimedOut.errorType, ErrorType.pipeline);
    });
    test('stepExitedNonzero rolls up to pipeline', () {
      expect(FailureType.stepExitedNonzero.errorType, ErrorType.pipeline);
    });
    test('stepProducedNoResult rolls up to pipeline', () {
      expect(FailureType.stepProducedNoResult.errorType, ErrorType.pipeline);
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
    test('providerNotConfigured overrides to configFault, not pipeline\'s default externalServiceFault', () {
      expect(FailureType.providerNotConfigured.faultClass, FaultClass.externalServiceFault);
      expect(FailureType.providerNotConfigured.effectiveFaultClass, FaultClass.configFault);
    });
    test('stepTimedOut overrides to transientFault, not pipeline\'s default externalServiceFault', () {
      expect(FailureType.stepTimedOut.faultClass, FaultClass.externalServiceFault);
      expect(FailureType.stepTimedOut.effectiveFaultClass, FaultClass.transientFault);
    });
    test('stepExitedNonzero uses its subsystem default, unoverridden', () {
      expect(FailureType.stepExitedNonzero.effectiveFaultClass, FaultClass.externalServiceFault);
    });
    test('stepProducedNoResult uses its subsystem default, unoverridden', () {
      expect(FailureType.stepProducedNoResult.effectiveFaultClass, FaultClass.externalServiceFault);
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

  // Exact-text assertions for the 4 new variants — an isNotEmpty check alone
  // doesn't catch a mutation to the string's *content* (confirmed real:
  // mutation testing found exactly this gap, character-level mutations
  // inside providerNotConfigured's and stepProducedNoResult's suggestedAction
  // text survived an isNotEmpty-only check). archiveIndexCorrupt has the
  // same gap but predates this session — filed as an issue, not fixed here.
  group('FailureType new-variant exact text', () {
    test('providerNotConfigured suggestedAction names every checked source', () {
      expect(
        FailureType.providerNotConfigured.suggestedAction,
        'Checked ANTHROPIC_API_KEY, Bedrock env vars, and '
        '~/.claude/settings.json -- none resolved. Run `claudart doctor` '
        'to diagnose.',
      );
    });
    test('stepTimedOut suggestedAction names the config key and the retry option', () {
      expect(
        FailureType.stepTimedOut.suggestedAction,
        'Raise or disable (0) "stepTimeoutMinutes" in the workspace '
        'config.json, or retry -- a slow response is not necessarily a '
        'broken one.',
      );
    });
    test('stepExitedNonzero suggestedAction points at the stderr output', () {
      expect(
        FailureType.stepExitedNonzero.suggestedAction,
        'Check the stderr output above for the real cause from `claude` '
        'itself.',
      );
    });
    test('stepProducedNoResult suggestedAction names the real condition', () {
      expect(
        FailureType.stepProducedNoResult.suggestedAction,
        'Re-run the step -- `claude` closed its stream without emitting a '
        'final result line.',
      );
    });
  });
}
