// failure_type.dart — bottom layer of claudart's error taxonomy
//
// Specific state-of-response. Each variant rolls up to one ErrorType (its
// subsystem) which rolls up to one FaultClass. Scoped to exactly the real
// exceptions this codebase throws (confirmed by reading every throw site)
// -- not speculatively extended for not-yet-built features (codegen,
// registry writes). Extend when a real throw site needs a new variant.
//
// The 4 `pipeline*` variants were added after the original 4 -- confirmed
// real gap: lib/pipeline/pipeline_executor.dart had 4 live bare
// `throw Exception(...)` sites that predated and bypassed this taxonomy
// entirely, not a deliberate exclusion.

import 'error_type.dart';
import 'fault_class.dart';

enum FailureType {
  scanThresholdExceeded,
  archiveIndexCorrupt,
  registryCorrupt,
  sessionCloseFailed,
  invalidHandoffTransition,
  workspaceLocked,
  providerNotConfigured,
  stepTimedOut,
  stepExitedNonzero,
  stepProducedNoResult;

  /// Parent subsystem for this failure. Rolls up to a FaultClass via
  /// `errorType.faultClass`.
  ErrorType get errorType => switch (this) {
        FailureType.scanThresholdExceeded => ErrorType.scan,
        FailureType.archiveIndexCorrupt => ErrorType.archive,
        FailureType.sessionCloseFailed ||
        FailureType.invalidHandoffTransition =>
          ErrorType.session,
        FailureType.workspaceLocked ||
        FailureType.registryCorrupt =>
          ErrorType.workspace,
        FailureType.providerNotConfigured ||
        FailureType.stepTimedOut ||
        FailureType.stepExitedNonzero ||
        FailureType.stepProducedNoResult =>
          ErrorType.pipeline,
      };

  /// Convenience getter — walks errorType → faultClass.
  FaultClass get faultClass => errorType.faultClass;

  /// Override the parent faultClass for variants whose category differs
  /// from their subsystem's default. `workspaceLocked` is on `workspace`
  /// (which defaults to environmentFault) but should classify as
  /// `transientFault` -- the lock clears itself once the other session
  /// finishes, so retrying is the right response, not asking the user to
  /// fix something. `providerNotConfigured` is on `pipeline` (which
  /// defaults to externalServiceFault) but is really a config problem --
  /// nothing about `claude` itself is misbehaving. `stepTimedOut` is also
  /// on `pipeline` but should classify as `transientFault` -- the same
  /// input may well succeed on retry (a slow model response, not a broken
  /// one). `stepProducedNoResult` is transient for the same reason: its own
  /// suggestedAction is "re-run the step", so classifying it as a
  /// non-retryable externalServiceFault would contradict the advice shown
  /// next to it.
  FaultClass get effectiveFaultClass => switch (this) {
        FailureType.workspaceLocked ||
        FailureType.stepTimedOut ||
        FailureType.stepProducedNoResult =>
          FaultClass.transientFault,
        FailureType.providerNotConfigured => FaultClass.configFault,
        _ => faultClass,
      };

  String get label => switch (this) {
        FailureType.scanThresholdExceeded => 'Scan threshold exceeded',
        FailureType.archiveIndexCorrupt => 'Archive index corrupt',
        FailureType.registryCorrupt => 'Registry corrupt',
        FailureType.sessionCloseFailed => 'Session close failed',
        FailureType.invalidHandoffTransition => 'Invalid handoff transition',
        FailureType.workspaceLocked => 'Workspace locked',
        FailureType.providerNotConfigured => 'Provider not configured',
        FailureType.stepTimedOut => 'Step timed out',
        FailureType.stepExitedNonzero => 'Step exited nonzero',
        FailureType.stepProducedNoResult => 'Step produced no result',
      };

  /// Actionable next step a user can take. Surfaces in caller-facing
  /// error messages.
  String get suggestedAction => switch (this) {
        FailureType.scanThresholdExceeded =>
          'Narrow the scan scope, or raise the threshold if the project '
              'genuinely is this large.',
        FailureType.archiveIndexCorrupt =>
          'Inspect archive/index.json by hand, or restore it from a backup '
              '-- it will not be silently overwritten.',
        FailureType.registryCorrupt =>
          'Inspect registry.json by hand, or restore it from a backup -- it '
              'will not be silently overwritten. `claudart doctor` reports '
              'it.',
        FailureType.sessionCloseFailed =>
          'Check the workspace state has been rolled back correctly, then '
              'retry the operation.',
        FailureType.invalidHandoffTransition =>
          'Run `claudart status` to see where the session is, then use the '
              'command that fits that status (docs/design.md lists the moves). '
              'If the status looks wrong, check handoff.md.',
        FailureType.workspaceLocked =>
          'Wait for the other session to finish, or confirm it has crashed '
              'before clearing the lock by hand.',
        FailureType.providerNotConfigured =>
          'Export ANTHROPIC_API_KEY, set the Bedrock env vars, or put them '
              'in the env block of ~/.claude/settings.json, then re-run.',
        FailureType.stepTimedOut =>
          'Retry the step -- a slow response is not necessarily a broken '
              'one.',
        FailureType.stepExitedNonzero =>
          'Check the stderr output above for the real cause from `claude` '
              'itself.',
        FailureType.stepProducedNoResult =>
          'Re-run the step -- `claude` closed its stream without emitting a '
              'final result line.',
      };
}
