// pipeline_step_exception.dart — typed exceptions for defaultClaudeRunner's
// 4 real failure conditions.
//
// Replaces 4 bare `throw Exception(...)` sites in pipeline_executor.dart that
// predated and bypassed claudart's error taxonomy (FaultClass/ErrorType/
// FailureType/ClaudartException, built in PR #72) -- confirmed real gap, not
// a design exclusion. One class per FailureType, matching the existing
// convention (ScanThresholdException, WorkspaceLockedException, etc.), not a
// single generic class taking a FailureType parameter.
//
// Every caller already catches `on Exception` and uses `.toString()`/`$e`
// interpolation (pipeline_executor.dart:143-144, :747) -- these satisfy that
// unchanged, since ClaudartException implements Exception.

import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';

class ProviderNotConfiguredException extends ClaudartException {
  ProviderNotConfiguredException() : super(FailureType.providerNotConfigured);

  @override
  String toString() =>
      'No agent provider configured (checked ANTHROPIC_API_KEY, Bedrock '
      'env vars, and ~/.claude/settings.json). Run `claudart doctor` to diagnose.';
}

class StepTimedOutException extends ClaudartException {
  final Duration timeout;

  StepTimedOutException(this.timeout) : super(FailureType.stepTimedOut);

  @override
  String toString() {
    final seconds = timeout.inSeconds;
    final after = seconds == 1 ? '1 second' : '$seconds seconds';
    return 'claude step timed out after $after and was killed. '
        'Raise or disable (0) "stepTimeoutMinutes" in the workspace config.json.';
  }
}

class StepExitedNonZeroException extends ClaudartException {
  final int exitCode;

  StepExitedNonZeroException(this.exitCode, {String? stderr})
      : super(FailureType.stepExitedNonzero, stderr: stderr);

  @override
  String toString() =>
      'claude exited $exitCode${stderr == null || stderr!.trim().isEmpty ? '' : ': ${stderr!.trim()}'}';
}

class StepProducedNoResultException extends ClaudartException {
  StepProducedNoResultException() : super(FailureType.stepProducedNoResult);

  @override
  String toString() => 'claude produced no result line';
}
