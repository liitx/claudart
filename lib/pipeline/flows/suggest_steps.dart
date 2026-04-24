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
import '../pipeline_context.dart';
import '../step_route.dart';

abstract final class SuggestSteps {
  // ── System prompts ──────────────────────────────────────────────────────────

  static const String _readerSystem =
      'You are a precise code reader. Read the listed files and report structured '
      'findings only. Do not explain, suggest, or implement anything.';

  static const String _reasonerSystem =
      'You are a precise technical analyst. Answer only what is asked. '
      'Output only the requested XML sections — no prose outside the tags.';

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

  /// Phase 2: sonnet reasons over findings, produces full XML analysis.
  static const AgentStep reasoner = AgentStep(
    id:           'reasoner',
    label:        'Reasoning over findings (sonnet)…',
    model:        AgentModel.sonnet,
    systemPrompt: _reasonerSystem,
    buildPrompt:  _reasonerPrompt,
    routes:       {}, // no routing — executor returns after this
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
      'CHANGES':  GoTo('applier'),
      'QUESTION': QuestionBranch('lookup'),
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
      'ANSWER':  FeedBackTo('planner'),
      'UNKNOWN': EscalateUser('planner'),
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
One bullet per file — path and what specifically needs to change.
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
  final analysis      = ctx.reasonerOut;
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
  final analysis = ctx.reasonerOut;

  return '''
Apply these changes to the analysis:

$changePlan

Existing analysis:
$analysis

Output all six XML sections. Only modify what the change plan specifies.
All other section content must be copied verbatim.
Tags: ROOT_CAUSE, SCOPE_FILES, SCOPE_ENTRIES, SCOPE_CLASSES, MUST_NOT_TOUCH, CONSTRAINTS.
No prose outside the tags.
''';
}

String _extractChanges(String plannerOutput) {
  final match = RegExp('<CHANGES>([\\s\\S]*?)</CHANGES>').firstMatch(plannerOutput);
  return match?.group(1)?.trim() ?? plannerOutput;
}
