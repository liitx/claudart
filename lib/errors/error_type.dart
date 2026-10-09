// error_type.dart — middle layer of claudart's error taxonomy
//
// Subsystem each fault originates from. Roll up to FaultClass via `faultClass`.
// Scoped to exactly the 4 subsystems with a real throw site today (scan,
// archive, session, workspace) -- not speculatively extended to subsystems
// (registry, git, codegen) that don't have one yet. Add a variant only
// when a real FailureType needs it, matching this project's own
// no-features-beyond-what's-used discipline.
//
// Adding a variant: declare the parent FaultClass in the exhaustive switch.
// Consumers that pattern-match on ErrorType get a compile error until they
// handle the new variant — the matrix grows by force.

import 'fault_class.dart';

enum ErrorType {
  scan,
  archive,
  session,
  workspace;

  /// Parent fault class for this subsystem. The chain rolls bottom-up so
  /// `FailureType.x.errorType.faultClass` resolves to the broadest category.
  FaultClass get faultClass => switch (this) {
        ErrorType.scan ||
        ErrorType.archive ||
        ErrorType.session ||
        ErrorType.workspace =>
          FaultClass.environmentFault,
      };

  String get label => switch (this) {
        ErrorType.scan => 'Scan',
        ErrorType.archive => 'Archive',
        ErrorType.session => 'Session',
        ErrorType.workspace => 'Workspace',
      };
}
