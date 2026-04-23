// pipeline_context.dart — immutable execution state passed between steps
//
// PipelineContext carries all named data slots that steps read and write,
// plus accumulated token usage and project-level inputs.
//
// Slots follow a naming convention:
//   step id         → e.g. ctx['reader'], ctx['reasoner'], ctx['planner']
//   __question__    → the pending question emitted by a QuestionBranch step
//   __clarification__ → accumulated answers (lookup + user) for planner re-runs
//   user_feedback   → refinement instruction typed by the user
//
// Immutability: all mutations return a new PipelineContext via withSlot/withUsage.
// This makes test assertions trivial — each call produces a predictable snapshot.

import 'usage.dart';

typedef ScopeFile = ({String relative, String absolute});

class PipelineContext {
  final Map<String, String> _slots;
  final Usage usage;
  final String projectRoot;
  final String bug;
  final String expected;
  final List<ScopeFile> files;

  const PipelineContext({
    Map<String, String> slots = const {},
    this.usage                = const Usage(),
    required this.projectRoot,
    required this.bug,
    required this.expected,
    required this.files,
  }) : _slots = slots;

  // ── Slot access ──────────────────────────────────────────────────────────────

  String? operator [](String key) => _slots[key];

  /// Returns a copy with [key] set to [value].
  PipelineContext withSlot(String key, String value) => PipelineContext(
    slots:       {..._slots, key: value},
    usage:       usage,
    projectRoot: projectRoot,
    bug:         bug,
    expected:    expected,
    files:       files,
  );

  /// Returns a copy with [newUsage] replacing the current usage.
  PipelineContext withUsage(Usage newUsage) => PipelineContext(
    slots:       _slots,
    usage:       newUsage,
    projectRoot: projectRoot,
    bug:         bug,
    expected:    expected,
    files:       files,
  );

  /// Appends [addition] to the `__clarification__` slot, separated by newline.
  PipelineContext appendClarification(String addition) {
    final existing = _slots['__clarification__'] ?? '';
    final updated  = existing.isEmpty ? addition : '$existing\n$addition';
    return withSlot('__clarification__', updated);
  }

  // ── Convenience accessors (step outputs) ────────────────────────────────────

  /// Output of the `reader` step (phase 1 file findings).
  String get readerOut => _slots['reader'] ?? '';

  /// Output of the `reasoner` step (phase 2 XML analysis).
  String get reasonerOut => _slots['reasoner'] ?? '';

  /// Output of the `applier` step (refined XML sections).
  String get applierOut => _slots['applier'] ?? '';

  /// Accumulated clarification for the planner re-run.
  String? get clarification => _slots['__clarification__'];
}
