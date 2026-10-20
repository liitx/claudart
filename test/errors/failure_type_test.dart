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
    test('invalidHandoffTransition rolls up to session', () {
      expect(FailureType.invalidHandoffTransition.errorType, ErrorType.session);
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
    test('invalidHandoffTransition uses its subsystem default, unoverridden',
        () {
      const failure = FailureType.invalidHandoffTransition;
      expect(failure.effectiveFaultClass, FaultClass.environmentFault);
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
    test('stepProducedNoResult overrides to transientFault, matching its "re-run the step" advice', () {
      expect(FailureType.stepProducedNoResult.faultClass, FaultClass.externalServiceFault);
      expect(FailureType.stepProducedNoResult.effectiveFaultClass, FaultClass.transientFault);
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
  group('FailureType.registryCorrupt', () {
    test('rolls up to workspace and keeps its default fault class', () {
      expect(FailureType.registryCorrupt.errorType, ErrorType.workspace);
      expect(
        FailureType.registryCorrupt.effectiveFaultClass,
        FaultClass.environmentFault,
      );
    });

    test('label and suggestedAction are exact', () {
      expect(FailureType.registryCorrupt.label, 'Registry corrupt');
      expect(
        FailureType.registryCorrupt.suggestedAction,
        'Inspect registry.json by hand, or restore it from a backup -- it '
        'will not be silently overwritten. `claudart doctor` reports it.',
      );
    });
  });

  group('FailureType new-variant exact text', () {
    test('providerNotConfigured suggestedAction says how to supply a provider', () {
      expect(
        FailureType.providerNotConfigured.suggestedAction,
        'Export ANTHROPIC_API_KEY, set the Bedrock env vars, or put them '
        'in the env block of ~/.claude/settings.json, then re-run.',
      );
    });
    test('stepTimedOut suggestedAction offers a retry, not a repeat of the exception message', () {
      expect(
        FailureType.stepTimedOut.suggestedAction,
        'Retry the step -- a slow response is not necessarily a broken '
        'one.',
      );
    });
    test('stepExitedNonzero suggestedAction points at the stderr output', () {
      expect(
        FailureType.stepExitedNonzero.suggestedAction,
        'Check the stderr output above for the real cause from `claude` '
        'itself.',
      );
    });
    test('invalidHandoffTransition suggestedAction says where to look', () {
      expect(
        FailureType.invalidHandoffTransition.suggestedAction,
        'Run `claudart status` to see where the session is, then use the '
        'command that fits that status (docs/design.md lists the moves). '
        'If the status looks wrong, check handoff.md.',
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

  // The failures of the debug apply path and of a step wired to a model its
  // role does not permit. One group per variant: where it rolls up, how it is
  // classified, and the exact words a person sees.
  group('$FailureType.editPlanMalformed', () {
    test('rolls up to pipeline with its default fault class', () {
      expect(FailureType.editPlanMalformed.errorType, ErrorType.pipeline);
      expect(
        FailureType.editPlanMalformed.effectiveFaultClass,
        FaultClass.externalServiceFault,
      );
    });

    test('label and suggestedAction are exact', () {
      expect(FailureType.editPlanMalformed.label, 'Edit plan malformed');
      expect(
        FailureType.editPlanMalformed.suggestedAction,
        'Re-run `claudart debug` -- the implementer output could not be '
        'split into complete file blocks. Nothing was written.',
      );
    });
  });

  group('$FailureType.editVerificationFailed', () {
    test('rolls up to pipeline with its default fault class', () {
      expect(FailureType.editVerificationFailed.errorType, ErrorType.pipeline);
      expect(
        FailureType.editVerificationFailed.effectiveFaultClass,
        FaultClass.externalServiceFault,
      );
    });

    test('label and suggestedAction are exact', () {
      expect(
        FailureType.editVerificationFailed.label,
        'Edit verification failed',
      );
      expect(
        FailureType.editVerificationFailed.suggestedAction,
        'The written files failed verification and were restored. Review '
        'the reported file and re-run `claudart debug`; the handoff '
        'status was not changed.',
      );
    });
  });

  group('$FailureType.stepModelNotPermittedForRole', () {
    test('rolls up to pipeline and classifies as a config fault', () {
      expect(
        FailureType.stepModelNotPermittedForRole.errorType,
        ErrorType.pipeline,
      );
      expect(
        FailureType.stepModelNotPermittedForRole.effectiveFaultClass,
        FaultClass.configFault,
      );
    });

    test('label and suggestedAction are exact', () {
      expect(
        FailureType.stepModelNotPermittedForRole.label,
        'Step model not permitted for its role',
      );
      expect(
        FailureType.stepModelNotPermittedForRole.suggestedAction,
        'A step was wired to a model its role does not permit (haiku may '
        'only classify and read). Fix the step or the routing so '
        'reasoning and implementation run on sonnet or opus.',
      );
    });
  });

  // The boundary's name for a failure no FailureType claims. It is a marker for
  // a gap in the taxonomy, so it is a programmer fault: every occurrence means
  // a variant is missing and should be defined.
  group('$FailureType.unexpectedFailure', () {
    test('rolls up to unclassified and classifies as a programmer fault', () {
      expect(FailureType.unexpectedFailure.errorType, ErrorType.unclassified);
      expect(
        FailureType.unexpectedFailure.effectiveFaultClass,
        FaultClass.programmerFault,
      );
    });

    test('label and suggestedAction are exact', () {
      expect(FailureType.unexpectedFailure.label, 'Unexpected failure');
      expect(
        FailureType.unexpectedFailure.suggestedAction,
        'No failure type describes this yet, so it is a gap in the failure '
        'taxonomy: define a FailureType for it. The reason above is the '
        'original error.',
      );
    });
  });
}
