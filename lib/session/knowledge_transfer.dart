// knowledge_transfer.dart — whether a handoff carries a knowledge transfer.
//
// The handoff is how one agent hands work to the next, so a handoff is only
// sufficient when it holds what the next agent needs: a root cause and the scope
// it applies to. This is derived from the handoff's content, never from its
// status line, so the two can be compared.

import 'handoff_section.dart';

/// Whether a handoff's content is a complete knowledge transfer.
enum KnowledgeTransfer {
  /// The root cause or the scope is still a placeholder.
  unconverged,

  /// Both the root cause and the scope hold real content.
  converged;

  /// The transfer a handoff with this [rootCause] and [scope] carries.
  static KnowledgeTransfer of({
    required HandoffSection rootCause,
    required HandoffSection scope,
  }) =>
      rootCause.isBlank || scope.isBlank ? unconverged : converged;
}

/// What a status claims about the handoff's knowledge transfer.
enum KnowledgeTransferExpectation {
  /// The status means the transfer is complete.
  converged,

  /// The status means the transfer is still being worked out.
  unconverged,

  /// The status says nothing about it (no session).
  none,
}
