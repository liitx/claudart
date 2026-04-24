// pipeline_context.dart — immutable execution state passed between steps
//
// PipelineContext carries all named data slots that steps read and write,
// plus accumulated token usage and project-level inputs.
//
// Slot access: prefer PipelineSlot enum values over raw strings.
//   ctx[PipelineSlot.plan]               — read
//   ctx.withSlot(PipelineSlot.flowExit, 'true')  — write
//
// String keys are still accepted so the executor can write step output by
// AgentStep.id without a static PipelineSlot reference.
//
// Immutability: all mutations return a new PipelineContext via withSlot/withUsage.

import 'pipeline_slot.dart';
import 'usage.dart';

export 'pipeline_slot.dart';

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

  /// Read a slot by [PipelineSlot] enum value or raw [String] key.
  String? operator [](Object key) =>
      _slots[key is PipelineSlot ? key.key : key as String];

  /// Returns a copy with [key] set to [value].
  /// [key] may be a [PipelineSlot] or a raw [String].
  PipelineContext withSlot(Object key, String value) {
    final k = key is PipelineSlot ? key.key : key as String;
    return PipelineContext(
      slots:       {..._slots, k: value},
      usage:       usage,
      projectRoot: projectRoot,
      bug:         bug,
      expected:    expected,
      files:       files,
    );
  }

  /// Returns a copy with [newUsage] replacing the current usage.
  PipelineContext withUsage(Usage newUsage) => PipelineContext(
    slots:       _slots,
    usage:       newUsage,
    projectRoot: projectRoot,
    bug:         bug,
    expected:    expected,
    files:       files,
  );

  /// Appends [addition] to the clarification slot, separated by newline.
  PipelineContext appendClarification(String addition) {
    final existing = _slots[PipelineSlot.clarification.key] ?? '';
    final updated  = existing.isEmpty ? addition : '$existing\n$addition';
    return withSlot(PipelineSlot.clarification, updated);
  }

  // ── Convenience accessors (step outputs) ────────────────────────────────────

  String get readerOut      => _slots[PipelineSlot.reader.key]      ?? '';
  String get reasonerOut    => _slots[PipelineSlot.reasoner.key]    ?? '';
  String get applierOut     => _slots[PipelineSlot.applier.key]     ?? '';
  String get implementerOut => _slots[PipelineSlot.implementer.key] ?? '';

  String? get clarification => _slots[PipelineSlot.clarification.key];

  // ── Checkpoint serialization ─────────────────────────────────────────────────

  Map<String, String> get slots => Map.unmodifiable(_slots);

  Map<String, Object> toCheckpointJson() => {
    'slots': Map.fromEntries(
      _slots.entries.where((e) => !PipelineSlot.values
          .any((s) => s.isControl && s.key == e.key)),
    ),
    'bug':         bug,
    'expected':    expected,
    'projectRoot': projectRoot,
  };

  factory PipelineContext.fromCheckpointJson(Map<String, dynamic> json) =>
      PipelineContext(
        slots:       Map<String, String>.from(json['slots'] as Map? ?? {}),
        bug:         json['bug']         as String? ?? '',
        expected:    json['expected']    as String? ?? '',
        projectRoot: json['projectRoot'] as String? ?? '',
        files:       [],
      );
}
