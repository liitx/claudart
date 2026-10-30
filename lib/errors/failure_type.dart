
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
// entirely, not a deliberate exclusion. The 2 `edit*` variants cover the
// debug apply path (lib/pipeline/edit_files.dart).

import 'error_type.dart';
import 'fault_class.dart';

enum FailureType {
  scanThresholdExceeded(
    errorType: ErrorType.scan,
    faultClassOverride: null,
    label: 'Scan threshold exceeded',
    suggestedAction: 'Narrow the scan scope, or raise the threshold if the '
                     'project genuinely is this large.',
  ),
  archiveIndexCorrupt(
    errorType: ErrorType.archive,
    faultClassOverride: null,
    label: 'Archive index corrupt',
    suggestedAction: 'Inspect archive/index.json by hand, or restore it from '
                     'a backup -- it will not be silently overwritten.',
  ),
  registryCorrupt(
    errorType: ErrorType.workspace,
    faultClassOverride: null,
    label: 'Registry corrupt',
    suggestedAction: 'Inspect registry.json by hand, or restore it from a '
                     'backup -- it will not be silently overwritten. '
                     '`claudart doctor` reports it.',
  ),
  sessionCloseFailed(
    errorType: ErrorType.session,
    faultClassOverride: null,
    label: 'Session close failed',
    suggestedAction: 'Check the workspace state has been rolled back '
                     'correctly, then retry the operation.',
  ),
  invalidHandoffTransition(
    errorType: ErrorType.session,
    faultClassOverride: null,
    label: 'Invalid handoff transition',
    suggestedAction: 'Run `claudart status` to see where the session is, then '
                     'use the command that fits that status (docs/design.md '
                     'lists the moves). If the status looks wrong, check '
                     'handoff.md.',
  ),
  workspaceLocked(
    errorType: ErrorType.workspace,
    faultClassOverride: FaultClass.transientFault,
    label: 'Workspace locked',
    suggestedAction: 'Wait for the other session to finish, or confirm it has '
                     'crashed before clearing the lock by hand.',
  ),
  providerNotConfigured(
    errorType: ErrorType.pipeline,
    faultClassOverride: FaultClass.configFault,
    label: 'Provider not configured',
    suggestedAction: 'Export ANTHROPIC_API_KEY, set the Bedrock env vars, or '
                     'put them in the env block of ~/.claude/settings.json, '
                     'then re-run.',
  ),
  stepTimedOut(
    errorType: ErrorType.pipeline,
    faultClassOverride: FaultClass.transientFault,
    label: 'Step timed out',
    suggestedAction: 'Retry the step -- a slow response is not necessarily a '
                     'broken one.',
  ),
  stepExitedNonzero(
    errorType: ErrorType.pipeline,
    faultClassOverride: null,
    label: 'Step exited nonzero',
    suggestedAction: 'Check the stderr output above for the real cause from '
                     '`claude` itself.',
  ),
  stepProducedNoResult(
    errorType: ErrorType.pipeline,
    faultClassOverride: FaultClass.transientFault,
    label: 'Step produced no result',
    suggestedAction: 'Re-run the step -- `claude` closed its stream without '
                     'emitting a final result line.',
  ),
  editPlanMalformed(
    errorType: ErrorType.pipeline,
    faultClassOverride: null,
    label: 'Edit plan malformed',
    suggestedAction: 'Re-run `claudart debug` -- the implementer output could '
                     'not be split into complete file blocks. Nothing was '
                     'written.',
  ),
  editVerificationFailed(
    errorType: ErrorType.pipeline,
    faultClassOverride: null,
    label: 'Edit verification failed',
    suggestedAction: 'The written files failed verification and were '
                     'restored. Review the reported file and re-run `claudart '
                     'debug`; the handoff status was not changed.',
  ),
  stepModelNotPermittedForRole(
    errorType: ErrorType.pipeline,
    faultClassOverride: FaultClass.configFault,
    label: 'Step model not permitted for its role',
    suggestedAction: 'A step was wired to a model its role does not permit '
                     '(haiku may only classify and read). Fix the step or the '
                     'routing so reasoning and implementation run on sonnet '
                     'or opus.',
  ),
  workspaceConfigUnreadable(
    errorType: ErrorType.workspace,
    faultClassOverride: FaultClass.configFault,
    label: 'Workspace config unreadable',
    suggestedAction: 'Fix or restore workspace.json by hand -- claudart never '
                     'overwrites it, and without it the owner settings (such '
                     'as strict mode) cannot be checked, so the command '
                     'stopped instead of assuming they are off.',
  ),
  tokenMapUnreadable(
    errorType: ErrorType.workspace,
    faultClassOverride: null,
    label: 'Token map unreadable',
    suggestedAction: 'Restore token_map.json from a backup or inspect it by '
                     'hand -- it is never overwritten, and without it a '
                     'sensitive project\'s identifiers cannot be abstracted, '
                     'so the command stopped instead of writing them out.',
  ),
  knowledgeTransferNotConverged(
    errorType: ErrorType.session,
    faultClassOverride: null,
    label: 'Knowledge transfer not converged',
    suggestedAction: 'The analysis did not name a root cause, so nothing was '
                     'written and the status is unchanged. Re-run `claudart '
                     'suggest`, or add a root cause to the handoff by hand.',
  ),
  homeDirectoryUnset(
    errorType: ErrorType.workspace,
    faultClassOverride: null,
    label: 'Home directory unset',
    suggestedAction: 'Set HOME, or set CLAUDART_WORKSPACE to an absolute '
                     'directory, then re-run.',
  ),
  handoffListenerFailed(
    errorType: ErrorType.session,
    faultClassOverride: null,
    label: 'Handoff listener failed',
    suggestedAction: 'A reaction to a status change threw. The move itself '
        'was written and recorded; read the reason above, then do by hand '
        'what that reaction does.',
  ),
  unexpectedFailure(
    errorType: ErrorType.unclassified,
    faultClassOverride: null,
    label: 'Unexpected failure',
    suggestedAction: 'No failure type describes this yet, so it is a gap in '
                     'the failure taxonomy: define a FailureType for it. The '
                     'reason above is the original error.',
  );

  const FailureType({
    required this.errorType,
    required this.faultClassOverride,
    required this.label,
    required this.suggestedAction,
  });

  /// Parent subsystem for this failure. Rolls up to a FaultClass via
  /// `errorType.faultClass`.
  final ErrorType errorType;

  /// The fault class for variants whose category differs from their
  /// subsystem's default, null when the subsystem's applies. `workspaceLocked`
  /// is on `workspace` (which defaults to environmentFault) but is a
  /// `transientFault` -- the lock clears itself once the other session
  /// finishes, so retrying is the right response. `providerNotConfigured` is
  /// on `pipeline` (which defaults to externalServiceFault) but is a config
  /// problem -- nothing about `claude` itself is misbehaving. `stepTimedOut`
  /// and `stepProducedNoResult` are transient: the same input may well
  /// succeed on retry, and the latter's own suggestedAction is "re-run the
  /// step", so a non-retryable class would contradict the advice shown next
  /// to it.
  final FaultClass? faultClassOverride;

  final String label;

  /// Actionable next step a user can take. Surfaces in caller-facing
  /// error messages.
  final String suggestedAction;

  /// Convenience getter — walks errorType → faultClass.
  FaultClass get faultClass => errorType.faultClass;

  FaultClass get effectiveFaultClass => faultClassOverride ?? faultClass;
}
