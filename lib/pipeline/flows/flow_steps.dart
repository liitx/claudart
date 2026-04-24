// flow_steps.dart — AgentStep definitions for the flow pipeline
//
// The flow pipeline is an agent-constructed session: the user provides a
// freeform prompt; agents categorize intent, generate a dependency-ordered
// plan, await approval, then construct the handoff automatically.
//
// Steps:
//   [categorize] haiku  — classifies input using the τ taxonomy; emits
//                         <CATEGORY>, <INTENT>, <COMPLEXITY>, <MODEL>
//   [plan]       sonnet — generates a dependency-ordered implementation plan;
//                         emits <PLAN> (ApprovalGate → construct) or
//                         <QUESTION> (QuestionBranch → clarify)
//   [clarify]    haiku  — resolves questions from plan against input context;
//                         emits <ANSWER> (FeedBackTo → plan) or
//                         <UNKNOWN> (EscalateUser → plan)
//   [construct]  sonnet — writes the full handoff structure from the approved
//                         plan; emits <HANDOFF> (Complete)
//
// Approval gate: plan → ApprovalGate('PLAN', 'construct')
//   User sees the plan before construct runs.
//   Declining aborts and yields PipelineCompleted with pre-construct ctx.

import '../agent_model.dart';
import '../agent_step.dart';
import '../pipeline_context.dart';
import '../step_route.dart';

abstract final class FlowSteps {
  static const String _categorizeSystem =
      'You are a precise task classifier. Classify the user input into exactly '
      'one AgentCategory (feature/bug/refactor/research/setup), one IntentClass '
      '(explore/analyze/implement/document), and one ComplexityTier '
      '(atomic/compound/systemic). Output only the four XML tags — no prose.';

  static const String _planSystem =
      'You are a dependency-ordered planner. Given a classified task, generate '
      'a structured implementation plan where each item lists what must exist '
      'before it can start. Output <PLAN>...</PLAN> with numbered items ordered '
      'by dependency, or <QUESTION>...</QUESTION> if critical context is missing.';

  static const String _clarifySystem =
      'You are a context resolver. Given a question and the original user input, '
      'determine if the answer can be inferred from what was provided. '
      'Output <ANSWER>...</ANSWER> if resolvable, or <UNKNOWN>...</UNKNOWN> if not.';

  static const String _constructSystem =
      'You are a handoff constructor. Given an approved plan, construct a '
      'complete handoff.md document. Output only <HANDOFF>...</HANDOFF> '
      'with these exact section headers in order:\n'
      '## Status\nready-for-suggest\n\n'
      '## Bug\n(concise bug or goal description)\n\n'
      '## Expected Behavior\n(what should happen)\n\n'
      '## Root Cause\n(key insight from the plan)\n\n'
      '## Scope\n'
      '### Files in play\n'
      '- `relative/path/to/file` — what changes\n\n'
      '### Must not touch\n(files or patterns to leave alone)\n\n'
      '## Constraints\n(implementation constraints from the plan)';

  // ── Steps ─────────────────────────────────────────────────────────────────

  static final AgentStep categorize = AgentStep(
    id:    'categorize',
    label: 'Categorizing intent',
    model: AgentModel.haiku,
    systemPrompt: _categorizeSystem,
    buildPrompt: (PipelineContext ctx) =>
        'Classify this task:\n\n${ctx.bug}',
    routes: const {},
  );

  static final AgentStep plan = AgentStep(
    id:    'plan',
    label: 'Generating plan',
    model: AgentModel.sonnet,
    systemPrompt: _planSystem,
    buildPrompt: (PipelineContext ctx) {
      final classification = ctx[PipelineSlot.categorize] ?? '';
      final clarification  = ctx.clarification ?? '';
      return [
        'Classification:\n$classification',
        'Task:\n${ctx.bug}',
        if (clarification.isNotEmpty) 'Additional context:\n$clarification',
      ].join('\n\n');
    },
    routes: {
      'PLAN':     const ApprovalGate(planTag: 'PLAN', nextStepId: 'construct'),
      'QUESTION': const QuestionBranch('clarify'),
    },
  );

  static final AgentStep clarify = AgentStep(
    id:    'clarify',
    label: 'Resolving question',
    model: AgentModel.haiku,
    systemPrompt: _clarifySystem,
    buildPrompt: (PipelineContext ctx) =>
        'Question: ${ctx[PipelineSlot.question] ?? ''}\n\nOriginal input: ${ctx.bug}',
    routes: {
      'ANSWER':  const FeedBackTo('plan'),
      'UNKNOWN': const EscalateUser('plan'),
    },
  );

  static final AgentStep construct = AgentStep(
    id:    'construct',
    label: 'Constructing handoff',
    model: AgentModel.sonnet,
    systemPrompt: _constructSystem,
    buildPrompt: (PipelineContext ctx) {
      final plan = ctx[PipelineSlot.plan] ?? '';
      return 'Approved plan:\n$plan\n\nOriginal task:\n${ctx.bug}';
    },
    routes: {
      'HANDOFF': const Complete(),
    },
  );

  static final List<AgentStep> all = [categorize, plan, clarify, construct];
}
