// closure_evidence.dart — what closed a handoff, and what an automatic close
// may do about it (docs/methodical_refactor.md, "Convergence closes with
// recorded evidence").
//
// The evidence is read from the handoff: its content, its status and the debug
// disposition it records. Only a fix a verification command passed archives;
// a handoff suggest confirmed ends as a reminder; anything less is left for
// the owner.

import 'debug_disposition.dart';
import 'knowledge_transfer.dart';
import 'session_state.dart';

/// What a converged handoff rests on.
enum ClosureEvidence {
  /// Debug ran and the workspace's verification command passed.
  verified('verified by a passing verification command'),

  /// `suggest` confirmed the transfer and debug was recorded as skipped or not
  /// applicable: no fix was verified.
  confirmedBySuggest('confirmed by suggest, no fix verified'),

  /// The transfer is converged but nothing records what happened to debug: it
  /// is pending, or the fix was applied and never verified.
  debugUnrecorded('converged, but no verified fix is recorded'),

  /// No evidence: the transfer is not converged, or the status says nothing.
  none('none yet');

  const ClosureEvidence(this.label);

  /// How `status` says it.
  final String label;
}

/// What an automatic close does for a piece of evidence.
enum AutomaticClosure {
  /// Run `teardown`: archive, and update what was learned.
  teardownAndArchive('an automatic close archives it and updates what was learned'),

  /// Run `teardown` as a reminder: nothing is learned from it.
  teardownAsReminder('an automatic close saves it as a reminder'),

  /// Do not run `teardown`; tell the owner the handoff is waiting.
  remindOwner('an automatic close waits for you'),

  /// Do nothing; the handoff stays open.
  stayOpen('nothing closes it');

  const AutomaticClosure(this.label);

  /// How `status` says it.
  final String label;
}

/// The evidence [state] carries.
ClosureEvidence closureEvidenceOf(SessionState state) {
  if (state.knowledgeTransfer != KnowledgeTransfer.converged) {
    return ClosureEvidence.none;
  }
  if (state.effectiveStatus.knowledgeTransferExpectation !=
      KnowledgeTransferExpectation.converged) {
    return ClosureEvidence.none;
  }
  return switch (state.debugDisposition) {
    DebugDisposition.verified => ClosureEvidence.verified,
    DebugDisposition.skipped ||
    DebugDisposition.notApplicable =>
      ClosureEvidence.confirmedBySuggest,
    DebugDisposition.done ||
    DebugDisposition.pending =>
      ClosureEvidence.debugUnrecorded,
  };
}

/// What an automatic close does for [evidence]. Exhaustive: a new kind of
/// evidence fails to compile until its exit is decided.
AutomaticClosure automaticClosureFor(ClosureEvidence evidence) =>
    switch (evidence) {
      ClosureEvidence.verified => AutomaticClosure.teardownAndArchive,
      ClosureEvidence.confirmedBySuggest => AutomaticClosure.teardownAsReminder,
      ClosureEvidence.debugUnrecorded => AutomaticClosure.remindOwner,
      ClosureEvidence.none => AutomaticClosure.stayOpen,
    };
