// fault_class.dart — top layer of claudart's error taxonomy
//
// Three-layer chain: FaultClass ← ErrorType ← FailureType
// Each FailureType belongs to exactly one ErrorType (its subsystem).
// Each ErrorType belongs to exactly one FaultClass (its fault category).
//
// Catching: consumers catch at the layer they own.
//   environmentFault → workspace / filesystem trouble (recoverable by user)
//   configFault      → config malformed (recoverable by editing config)
//   externalServiceFault → an external tool/API failure (may be transient)
//   transientFault   → retry later
//   programmerFault  → invariant violation, code bug
//
// Named FaultClass (not Exception) to avoid shadowing dart:core Exception.
// Throwable wrapper is ClaudartException — see claudart_exception.dart.
//
// Lives in claudart, not dartrix: dartrix is a dev-only dependency here
// (see pubspec.yaml's dependency ledger) -- promoting it to a real
// dependency just to share this 5-variant enum is a real, visible cost,
// and duplicating it in both claudart and zedup would recreate exactly
// the redundancy this taxonomy exists to remove. zedup already depends
// on claudart as a real dependency and imports 30+ of its types, so
// hosting this here adds zero new dependency edges. Shape mirrors
// zedup's own FaultClass (lib/src/enums/fault_class.dart) exactly --
// confirmed proven in real code there before being adopted here.

enum FaultClass {
  environmentFault,
  configFault,
  externalServiceFault,
  transientFault,
  programmerFault;

  String get label => switch (this) {
        FaultClass.environmentFault => 'Environment fault',
        FaultClass.configFault => 'Config fault',
        FaultClass.externalServiceFault => 'External service fault',
        FaultClass.transientFault => 'Transient fault',
        FaultClass.programmerFault => 'Programmer fault',
      };

  /// Severity ordering: info < warn < error < fatal.
  /// Programmer faults are fatal — they signal an invariant violation.
  /// Transient faults are warn — caller usually retries.
  /// Everything else defaults to error.
  FaultSeverity get severity => switch (this) {
        FaultClass.programmerFault => FaultSeverity.fatal,
        FaultClass.transientFault => FaultSeverity.warn,
        FaultClass.environmentFault ||
        FaultClass.configFault ||
        FaultClass.externalServiceFault =>
          FaultSeverity.error,
      };

  /// True when retry-with-same-input could succeed without user action.
  bool get retryable => switch (this) {
        FaultClass.transientFault => true,
        FaultClass.environmentFault ||
        FaultClass.configFault ||
        FaultClass.externalServiceFault ||
        FaultClass.programmerFault =>
          false,
      };
}

enum FaultSeverity {
  info,
  warn,
  error,
  fatal;

  /// True when the severity warrants stopping execution.
  bool get blocking => switch (this) {
        FaultSeverity.fatal || FaultSeverity.error => true,
        FaultSeverity.warn || FaultSeverity.info => false,
      };
}
