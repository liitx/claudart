// debug_disposition.dart — where debug stands for a handoff, as the handoff
// records it.
//
// Whether debug has been run, still will be, need not be, or was deliberately
// not used is a decision about the handoff, so it is written into the handoff
// instead of being guessed from whether debug happened to run. A handoff that
// is resolved as far as debug goes is one `teardown` may close.

import 'handoff_placeholder.dart';

/// Where debug stands for a handoff.
enum DebugDisposition {
  /// Debug applies and has not finished: it may still run.
  pending('pending', recordsAppliedFix: false),

  /// Debug ran and the fix was applied; nothing but `dart analyze` checked it.
  done('done', recordsAppliedFix: true),

  /// Debug ran, the fix was applied, and the workspace's verification command
  /// passed. The only disposition that counts as verified evidence.
  verified('verified', recordsAppliedFix: true),

  /// The kind of work has no debug step, such as an analysis that resolves it.
  notApplicable('not-applicable', recordsAppliedFix: false),

  /// Debug applies but will not be used; this was decided, not forgotten.
  skipped('skipped', recordsAppliedFix: false);

  const DebugDisposition(this.wire, {required this.recordsAppliedFix});

  /// How the disposition is written in the handoff.
  final String wire;

  /// Whether the disposition says a fix was applied, so only a finished fix
  /// (`debugComplete`) goes with it.
  final bool recordsAppliedFix;

  /// Whether the handoff is resolved as far as debug goes: nothing is left for
  /// debug to do.
  bool get isResolved => switch (this) {
        pending => false,
        done || verified || notApplicable || skipped => true,
      };

  /// The disposition written as [text], or null when [text] is empty, a
  /// placeholder, or not a spelling this enum owns. An unknown spelling is
  /// never guessed.
  static DebugDisposition? fromWire(String text) {
    final trimmed = text.trim();
    if (HandoffPlaceholder.isBlank(trimmed)) return null;
    for (final disposition in values) {
      if (disposition.wire == trimmed) return disposition;
    }
    return null;
  }
}
