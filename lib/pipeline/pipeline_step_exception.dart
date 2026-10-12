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
// PipelineExecutor catches `on Exception` around the runner call and keeps
// `e.toString()` as AgentFailed.reason, so these work there unchanged
// (ClaudartException implements Exception); only the generic "Exception: "
// prefix is gone. The chat shell's plain-message path has no catch of its own,
// so there these now reach bin/claudart.dart's central ClaudartException
// handler instead of surfacing as an unhandled exception.

import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';

/// "15 minutes", "1 minute", "90 seconds", "1 second" -- whole minutes read as
/// minutes, anything else as seconds. Shared by [StepTimedOutException] and the
/// executor's debug trace so the two can never describe the same limit
/// differently.
String describeDuration(Duration d) {
  if (d.inMinutes >= 1 && d.inSeconds % 60 == 0) {
    final m = d.inMinutes;
    return m == 1 ? '1 minute' : '$m minutes';
  }
  final s = d.inSeconds;
  return s == 1 ? '1 second' : '$s seconds';
}

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
  String toString() =>
      'claude step timed out after ${describeDuration(timeout)} and was killed. '
      'Raise or disable (0) "stepTimeoutMinutes" in the workspace config.json.';
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
