// handoff_finding.dart — a way a handoff's status and its content disagree.

/// One disagreement between what a handoff's status claims and what its content
/// holds. A consistent handoff has none.
enum HandoffFinding {
  /// The status says the knowledge transfer is complete, but the root cause or
  /// the scope is still a placeholder.
  statusAheadOfContent,

  /// The root cause and the scope are real, but the status still says the
  /// transfer is being worked out.
  contentAheadOfStatus,

  /// The recorded debug disposition contradicts the status: only a finished fix
  /// is `done`, and a finished fix is nothing else.
  debugDispositionDisagrees;

  /// What the disagreement is, in a sentence.
  String get description => switch (this) {
        statusAheadOfContent => 'The status says the knowledge transfer is '
            'complete, but the root cause or scope is still a placeholder.',
        contentAheadOfStatus => 'The root cause and scope are filled in, but '
            'the status still says the knowledge transfer is in progress.',
        debugDispositionDisagrees => 'The recorded debug disposition does not '
            'match the status: only a finished fix is done.',
      };
}
