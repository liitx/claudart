// failure_type.dart — bottom layer of claudart's error taxonomy
//
// Specific state-of-response. Each variant rolls up to one ErrorType (its
// subsystem) which rolls up to one FaultClass. Scoped to exactly the 4
// real exceptions this codebase already throws (confirmed by reading
// every throw site) -- not speculatively extended for not-yet-built
// features (codegen, registry writes). Extend when a real throw site
// needs a new variant.

import 'error_type.dart';
import 'fault_class.dart';

enum FailureType {
  scanThresholdExceeded,
  archiveIndexCorrupt,
  sessionCloseFailed,
  workspaceLocked;

  /// Parent subsystem for this failure. Rolls up to a FaultClass via
  /// `errorType.faultClass`.
  ErrorType get errorType => switch (this) {
        FailureType.scanThresholdExceeded => ErrorType.scan,
        FailureType.archiveIndexCorrupt => ErrorType.archive,
        FailureType.sessionCloseFailed => ErrorType.session,
        FailureType.workspaceLocked => ErrorType.workspace,
      };

  /// Convenience getter — walks errorType → faultClass.
  FaultClass get faultClass => errorType.faultClass;

  /// Override the parent faultClass for variants whose category differs
  /// from their subsystem's default. `workspaceLocked` is on `workspace`
  /// (which defaults to environmentFault) but should classify as
  /// `transientFault` -- the lock clears itself once the other session
  /// finishes, so retrying is the right response, not asking the user to
  /// fix something.
  FaultClass get effectiveFaultClass => switch (this) {
        FailureType.workspaceLocked => FaultClass.transientFault,
        _ => faultClass,
      };

  String get label => switch (this) {
        FailureType.scanThresholdExceeded => 'Scan threshold exceeded',
        FailureType.archiveIndexCorrupt => 'Archive index corrupt',
        FailureType.sessionCloseFailed => 'Session close failed',
        FailureType.workspaceLocked => 'Workspace locked',
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
        FailureType.sessionCloseFailed =>
          'Check the workspace state has been rolled back correctly, then '
              'retry the operation.',
        FailureType.workspaceLocked =>
          'Wait for the other session to finish, or confirm it has crashed '
              'before clearing the lock by hand.',
      };
}
