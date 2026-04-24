// pipeline_slot.dart — canonical registry of all named context slots
//
// Every slot key used by PipelineContext lives here as a PipelineSlot enum
// value. Raw strings are banned — use PipelineSlot everywhere so that:
//   • A slot's consumers can be found by "Find usages of PipelineSlot.X"
//   • Typos are compile errors, not silent misses
//   • _noCheckpoint and isControl are derivable from the enum, not a parallel
//     set of magic strings
//
// Step output slots (isControl = false): named after the AgentStep.id that
// writes them.  Control slots (isControl = true): named with __ prefix to
// signal they are ephemeral pipeline state, not domain output.

enum PipelineSlot {
  // ── Step output slots ────────────────────────────────────────────────────
  categorize('categorize'),
  plan('plan'),
  clarify('clarify'),
  construct('construct'),
  reader('reader'),
  reasoner('reasoner'),
  planner('planner'),
  applier('applier'),
  implementer('implementer'),
  userFeedback('user_feedback'),

  // ── Control slots ────────────────────────────────────────────────────────
  question('__question__'),
  clarification('__clarification__'),
  flowExit('__flow_exit__'),
  approved('__approved__');

  const PipelineSlot(this.key);

  /// The raw string key written into the PipelineContext slot map.
  final String key;

  /// True for internal pipeline control slots (__ prefix).
  /// Control slots are not persisted to checkpoint files.
  bool get isControl => key.startsWith('__');
}
