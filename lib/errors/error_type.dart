// error_type.dart — middle layer of claudart's error taxonomy
//
// Subsystem each fault originates from. Roll up to FaultClass via `faultClass`.
// Scoped to exactly the 5 subsystems with a real throw site today (scan,
// archive, session, workspace, pipeline) -- not speculatively extended to
// subsystems (registry, git, codegen) that don't have one yet. Add a variant
// only when a real FailureType needs it, matching this project's own
// no-features-beyond-what's-used discipline.
//
// `pipeline` added after the original 4 -- confirmed real gap, not a design
// exclusion: lib/pipeline/pipeline_executor.dart (the engine that runs every
// `claude` subprocess step) had 4 live throw sites using bare, untyped
// `Exception(...)`, bypassing this taxonomy entirely since it was built.
//
// Adding a variant: declare the parent FaultClass in the exhaustive switch.
// Consumers that pattern-match on ErrorType get a compile error until they
// handle the new variant — the matrix grows by force.

import 'fault_class.dart';

enum ErrorType {
  scan(label: 'Scan', faultClass: FaultClass.environmentFault),
  archive(label: 'Archive', faultClass: FaultClass.environmentFault),
  session(label: 'Session', faultClass: FaultClass.environmentFault),
  workspace(label: 'Workspace', faultClass: FaultClass.environmentFault),

  /// The `claude` subprocess itself is an external tool from claudart's
  /// perspective -- most pipeline failures are it misbehaving, not claudart's
  /// own environment. FailureType-level overrides exist for the variants that
  /// are genuinely config/transient instead (see failure_type.dart's
  /// faultClassOverride).
  pipeline(label: 'Pipeline', faultClass: FaultClass.externalServiceFault),

  /// A failure no other subsystem claims. It marks a gap in the taxonomy, so
  /// every occurrence should be given a real [FailureType] and subsystem. A
  /// gap in claudart's own taxonomy, not an outside failure.
  unclassified(label: 'Unclassified', faultClass: FaultClass.programmerFault);

  const ErrorType({required this.label, required this.faultClass});

  final String label;

  /// Parent fault class for this subsystem. The chain rolls bottom-up so
  /// `FailureType.x.errorType.faultClass` resolves to the broadest category.
  final FaultClass faultClass;
}
