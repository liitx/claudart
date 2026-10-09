// claudart_exception.dart — throwable wrapper around a FailureType + context
//
// Wraps a FailureType with a context map and an optional stderr payload.
// Implements dart:core's Exception so callers can `throw` it and `catch`
// it with the language's exception machinery.
//
// Usage:
//   throw ClaudartException(
//     FailureType.workspaceLocked,
//     context: {'workspacePath': workspacePath},
//   );
//
// Caller catches at the layer they own:
//   on ClaudartException catch (e) when (e.failureType == FailureType.workspaceLocked) { ... }
//   on ClaudartException catch (e) when (e.faultClass == FaultClass.transientFault) { retry; }
//
// Mirrors zedup's own ZedupException (lib/src/errors/zedup_exception.dart)
// exactly -- same shape, proven in real code there first.

import 'error_type.dart';
import 'failure_type.dart';
import 'fault_class.dart';

class ClaudartException implements Exception {
  ClaudartException(
    this.failureType, {
    this.context = const {},
    this.stderr,
  });

  final FailureType failureType;

  /// Caller-supplied details (workspace path, exit code, file path, etc.).
  final Map<String, String> context;

  /// Verbatim stderr from a subprocess call, when applicable.
  final String? stderr;

  /// Convenience getter — walks failureType → errorType.
  ErrorType get errorType => failureType.errorType;

  /// Convenience getter — walks failureType → errorType → faultClass.
  /// Uses `effectiveFaultClass` so variants that override their default
  /// (e.g. workspaceLocked → transientFault) resolve correctly.
  FaultClass get faultClass => failureType.effectiveFaultClass;

  @override
  String toString() {
    final ctx = context.isEmpty
        ? ''
        : ' ${context.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    final err = stderr == null || stderr!.isEmpty ? '' : '\n  stderr: $stderr';
    return 'ClaudartException(${failureType.name}$ctx)$err';
  }
}
