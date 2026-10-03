// suggest_steps.dart — AgentStep definitions for the suggest pipeline
//
// The suggest pipeline has two phases and a refinement loop:
//
//   Phase 1: [reader]   haiku  — reads scope files, emits structured findings
//   Phase 2: [reasoner] sonnet — reasons over findings, emits XML analysis
//
//   Refinement (called on [r] in review loop):
//     [planner]  sonnet — plans changes from feedback; emits <CHANGES> or <QUESTION>
//     [lookup]   haiku  — searches phase1 findings for an answer; emits <ANSWER> or <UNKNOWN>
//     [applier]  haiku  — applies the change plan surgically; emits updated XML sections
//
// Routing (refinement only):
//   planner: CHANGES   → GoTo('applier')
//            QUESTION  → QuestionBranch('lookup')
//   lookup:  ANSWER    → FeedBackTo('planner')
//            UNKNOWN   → EscalateUser(returnToStepId: 'planner')
//   applier: (no routes → executor returns updated context)

import '../agent_model.dart';
import '../agent_step.dart';
import '../agents/categorization.dart';
import '../pipeline_context.dart';
import '../route_tag.dart';
import '../step_route.dart';

abstract final class SuggestSteps {
  // ── System prompts ──────────────────────────────────────────────────────────

  static const String _readerSystem =
      'You are a precise code reader. Read the listed files and report structured '
      'findings only. Do not explain, suggest, or implement anything.';

  static const String _reasonerSystem =
      'You are a precise technical analyst. Answer only what is asked. '
      'Output only the requested XML sections — no prose outside the tags. '
      'Only reference file paths, directory structures, and type names that appear '
      'explicitly in the findings provided. Do not invent paths, conventions, or '
      'types from external frameworks or prior knowledge.';

  // ── Phase steps (run once per suggest invocation) ───────────────────────────

  /// Phase 1: haiku reads every scope file and reports findings.
  /// The label includes the file count, so it's built dynamically.
  static AgentStep reader(int fileCount) => AgentStep(
    id:           'reader',
    label:        'Reading $fileCount scope files (haiku)…',
    model:        AgentModel.haiku,
    systemPrompt: _readerSystem,
    buildPrompt:  _readerPrompt,
    routes:       const {}, // falls through to reasoner
  );

  /// Phase 2: reasons over findings, produces full XML analysis. Model
  /// is dynamic — [_reasonerModelSelector] consults the categorize
  /// step's output (Phase 0) via [routeModel], so a `gui × design`
  /// session gets opus reasoning instead of the sonnet default.
  static const AgentStep reasoner = AgentStep(
    id:            'reasoner',
    label:         'Reasoning over findings…',
    model:         AgentModel.sonnet,
    modelSelector: _reasonerModelSelector,
    systemPrompt:  _reasonerSystem,
    buildPrompt:   _reasonerPrompt,
    routes:        {}, // no routing — executor returns after this
  );

  /// Reads the categorize step's `<CATEGORY>`/`<INTENT>`/`<COMPLEXITY>`
  /// output (written to `PipelineSlot.categorize` by the Phase 0
  /// categorize step this session ran) and consults [routeModel]. Falls
  /// back to sonnet — the pre-existing static default — when the slot
  /// is empty or unparsable.
  static AgentModel _reasonerModelSelector(PipelineContext ctx) =>
      modelForCategorizeOutput(
        ctx[PipelineSlot.categorize] ?? '',
        fallback: AgentModel.sonnet,
      );

  // ── Refinement steps (run in loop after user says [r]) ───────────────────────

  /// Planner: given the current analysis + user feedback, determines what to change.
  /// Emits `CHANGES` when clear; emits `QUESTION` when it needs codebase information.
  static AgentStep planner(int pass) => AgentStep(
    id:           'planner',
    label:        'Planning changes (sonnet)… pass $pass',
    model:        AgentModel.sonnet,
    systemPrompt: _reasonerSystem,
    buildPrompt:  _plannerPrompt,
    routes: const {
      RouteTag.changes:  GoTo('applier'),
      RouteTag.question: QuestionBranch('lookup'),
    },
  );

  /// Lookup: searches phase1 findings to answer the planner's question.
  /// Emits `ANSWER` when found; emits `UNKNOWN` when not determinable.
  static AgentStep lookup(int pass) => AgentStep(
    id:           'lookup',
    label:        'Looking up in scope files (haiku)… pass $pass',
    model:        AgentModel.haiku,
    systemPrompt: _readerSystem,
    buildPrompt:  _lookupPrompt,
    routes: const {
      RouteTag.answer:  FeedBackTo('planner'),
      RouteTag.unknown: EscalateUser('planner'),
    },
  );

  /// Applier: receives the change plan and surgically updates XML sections.
  /// No routes — executor returns updated ctx after this runs.
  static AgentStep applier(int pass) => AgentStep(
    id:           'applier',
    label:        'Applying changes (haiku)… pass $pass',
    model:        AgentModel.haiku,
    systemPrompt: _reasonerSystem,
    buildPrompt:  _applierPrompt,
    routes:       const {}, // terminal
    postProcess:  _mergeAnalysis,
  );

  // ── Convenience builders ────────────────────────────────────────────────────

  /// The two linear phase steps [reader, reasoner].
  static List<AgentStep> phases(int fileCount) => [reader(fileCount), reasoner];

  /// The three refinement steps for a given [pass] number.
  static List<AgentStep> refinement(int pass) => [
    planner(pass),
    lookup(pass),
    applier(pass),
  ];
}

// ── Prompt builders ───────────────────────────────────────────────────────────

String _readerPrompt(PipelineContext ctx) => '''
Bug context: ${ctx.bug}

Read each file below. For each output exactly this block:

=== FILE: <path> ===
EXISTS: yes | no
RELEVANT_LINES:
<paste the exact lines most relevant to the bug, or "none">
MISSING:
<what is absent that the bug implies should be here, or "nothing">

Files to read:
${ctx.files.map((f) => f.absolute).join('\n')}
''';

String _reasonerPrompt(PipelineContext ctx) => '''
Bug: ${ctx.bug}

Expected behavior: ${ctx.expected}

File findings:
${ctx.readerOut}

Answer each section. Use exact XML tags. Cite specific file paths and line numbers.

<ROOT_CAUSE>
What is missing or broken, referencing exact files.
</ROOT_CAUSE>

<SCOPE_FILES>
One bullet per file, in exactly this form (path relative to the project root, in backticks, then an em dash):
- `relative/path/to/file.dart` — what specifically needs to change
</SCOPE_FILES>

<SCOPE_ENTRIES>
Key entry point classes, methods, or functions.
</SCOPE_ENTRIES>

<SCOPE_CLASSES>
Classes and methods in play relevant to the fix.
</SCOPE_CLASSES>

<MUST_NOT_TOUCH>
Files, classes, or patterns that must not be modified.
</MUST_NOT_TOUCH>

<CONSTRAINTS>
Constraints on how the fix must be implemented.
</CONSTRAINTS>
''';

String _plannerPrompt(PipelineContext ctx) {
  final analysis      = _latestAnalysis(ctx);
  final feedback      = ctx[PipelineSlot.userFeedback] ?? '';
  final clarification = ctx.clarification;
  final planContext   = clarification != null
      ? '$feedback\n\n$clarification'
      : feedback;

  return '''
Current analysis:
$analysis

User feedback: $planContext

Identify exactly what the feedback requires changing.
Do NOT guess or infer beyond what is explicitly stated.

If the required changes are clear, output:
<CHANGES>
One line per section that needs updating — section name and the specific change.
Sections not mentioned stay identical.
</CHANGES>

If anything is ambiguous or requires information not present above, output:
<QUESTION>
One specific question to ask before proceeding.
</QUESTION>

No prose outside the tags.
''';
}

String _lookupPrompt(PipelineContext ctx) {
  final question = ctx[PipelineSlot.question] ?? '';
  return '''
Question: $question

Phase 1 already read the scope files. Search the findings below to answer.
Do NOT re-read files — only use what is here.

<ANSWER>
The specific answer, with file path and line reference from the findings.
</ANSWER>

If the findings do not contain enough to answer without guessing:
<UNKNOWN>
What is absent from the findings that would be needed.
</UNKNOWN>

No prose outside the tags.

Phase 1 findings:
${ctx.readerOut}
''';
}

String _applierPrompt(PipelineContext ctx) {
  final changePlan = ctx[PipelineSlot.planner] != null
      ? _extractChanges(ctx[PipelineSlot.planner]!)
      : '';
  final analysis   = _latestAnalysis(ctx);
  final targets    = _parseTargetSections(changePlan);
  final extracted  = targets.map((t) => _extractSection(analysis, t)).toList();
  // Fall back to the full analysis if any targeted tag failed to extract
  // (e.g. the model forgot to emit it) — silently dropping just that
  // section would ask the applier to update a section it never sees.
  final missingTarget = targets.isNotEmpty && extracted.any((s) => s.isEmpty);
  final sections = targets.isEmpty || missingTarget
      ? analysis
      : extracted.join('\n\n');

  // When a targeted section is missing, the plain "don't output anything
  // not shown above" instruction would forbid the applier from ever
  // emitting the very section it's supposed to add — _mergeAnalysis()
  // can append a genuinely new section, but only if the applier is
  // allowed to output one.
  final outputConstraint = missingTarget
      ? 'Output ONLY the sections targeted by the change plan '
        '(${targets.join(', ')}), using their exact XML tags — including '
        'any of those tags not shown in the analysis above, since they '
        'need to be added. Do not output any other section.'
      : 'Output ONLY the sections listed above using their exact XML tags.\n'
        'Do not output any section not shown above.';

  return '''
Apply these changes:

$changePlan

To these sections only:

$sections

$outputConstraint
No prose outside the tags.
''';
}

// ── Applier helpers ───────────────────────────────────────────────────────────

const _kSections = {
  'ROOT_CAUSE', 'SCOPE_FILES', 'SCOPE_ENTRIES',
  'SCOPE_CLASSES', 'MUST_NOT_TOUCH', 'CONSTRAINTS',
};

// Returns the latest full analysis: applier output supersedes reasoner output.
String _latestAnalysis(PipelineContext ctx) =>
    ctx.applierOut.isNotEmpty ? ctx.applierOut : ctx.reasonerOut;

// Identifies which sections the change plan targets by scanning for tag names.
Set<String> _parseTargetSections(String changePlan) =>
    _kSections.where((s) => changePlan.contains(s)).toSet();

// Extracts a single <TAG>...</TAG> block from an XML document.
String _extractSection(String xml, String tag) {
  final m = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
  return m != null ? '<$tag>${m.group(1)}</$tag>' : '';
}

// Merges the applier's partial output (changed sections only) back into the
// full analysis document. Called as AgentStep.postProcess so the context slot
// always holds a complete document, not a partial one.
String _mergeAnalysis(String partial, PipelineContext ctx) {
  var merged = _latestAnalysis(ctx);
  for (final tag in _kSections) {
    final updated = _extractSection(partial, tag);
    if (updated.isEmpty) continue;
    final existing = RegExp('<$tag>[\\s\\S]*?</$tag>');
    // replaceFirst is a no-op when the tag isn't in `merged` at all — the
    // exact case _applierPrompt's own fallback exists for (analysis
    // missing a targeted section). If the applier actually emitted that
    // section, appending it must not be silently dropped just because
    // there was nothing to replace.
    merged = existing.hasMatch(merged)
        ? merged.replaceFirst(existing, updated)
        : '$merged\n$updated';
  }
  return merged;
}

String _extractChanges(String plannerOutput) {
  final match = RegExp('<CHANGES>([\\s\\S]*?)</CHANGES>').firstMatch(plannerOutput);
  return match?.group(1)?.trim() ?? plannerOutput;
}
