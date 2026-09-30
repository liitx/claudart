// agent_step.dart — a single step in an agent pipeline
//
// An AgentStep is a self-contained unit of work:
//   - which model to call (or how to pick one from context)
//   - what system prompt to use
//   - how to build the message from current context
//   - which XML tag in the output triggers which route
//
// Model selection:
//   - `model` is the static choice used when [modelSelector] is unset
//     (most steps — categorize, clarify, construct, etc.).
//   - [modelSelector] is the dynamic hook — the executor calls it once
//     per step with the current [PipelineContext] so the categorize
//     step's classification can drive downstream model choice. The
//     selector contract is *total*: it must return an [AgentModel],
//     not null. Selectors that want fallback behaviour on malformed
//     input embed it themselves (see [modelForCategorizeOutput]'s
//     required `fallback:` parameter) — keeping the fallback at the
//     selector site rather than in [effectiveModel] eliminates the
//     "silent fall through to step.model" drift seam.
//
// Routing:
//   routes is empty  → no branching; executor proceeds to next step in list
//   routes non-empty → executor parses output for first matching tag, routes accordingly
//
// All prompt building is deferred to buildPrompt(ctx) so steps are pure
// data — no I/O at declaration time. Tests can inject any PipelineContext.

import 'agent_model.dart';
import 'pipeline_context.dart';
import 'route_tag.dart';
import 'step_mode.dart';
import 'step_route.dart';
import 'tool_grant.dart';

/// Resolves a step's model from the current [PipelineContext]. Total
/// — must return an [AgentModel]. Selectors that need a fallback for
/// malformed context embed it themselves (see
/// [modelForCategorizeOutput]'s required `fallback:` parameter). Pure
/// — no IO.
typedef ModelSelector = AgentModel Function(PipelineContext ctx);

class AgentStep {
  final String id;
  final String label;

  /// Static model used when [modelSelector] is unset. Steps that
  /// don't need dynamic routing leave [modelSelector] null and read
  /// this directly. Selectors, when present, are total — they own
  /// their own fallback semantics, so this field is *not* consulted
  /// once a selector is wired.
  final AgentModel model;

  final String systemPrompt;
  final String Function(PipelineContext ctx) buildPrompt;

  /// Dynamic model resolver. Lets downstream steps pick a model based
  /// on what an earlier step produced (e.g. plan step reads the
  /// categorize step's `<COMPLEXITY>` tag to route atomic tasks to
  /// haiku). Null means "use [model] always."
  final ModelSelector? modelSelector;

  /// Tag-to-route map. Keys are typed [RouteTag] variants (not raw
  /// strings) so a rename of any wire-format tag is a single switch
  /// arm change in `route_tag.dart`. The executor finds the first
  /// tag present in the step's output and follows its route. Order
  /// matters: entries are checked in insertion order (Dart Map
  /// preserves insertion order).
  final Map<RouteTag, StepRoute> routes;

  /// Optional post-processor applied to the raw step output before it is
  /// stored in the context. Receives the raw output and the pre-storage
  /// context. Use this to merge partial outputs (e.g. applier sections) back
  /// into a full document without sending the full document to the model.
  final String Function(String output, PipelineContext ctx)? postProcess;

  /// How the claude subprocess is invoked for this step. [StepMode.bare]
  /// passes `--bare` — use for steps that must output structured text
  /// only, since it prevents a project CLAUDE.md from overriding the
  /// system prompt with agent-mode instructions.
  ///
  /// [StepMode.bare] is not just a formatting toggle: `--bare` strictly
  /// requires `ANTHROPIC_API_KEY` or an `apiKeyHelper` and never reads
  /// OAuth or keychain credentials (verified live — a normal
  /// OAuth-logged-in session gets "Not logged in" under `--bare`). Since
  /// this pipeline's standard auth path is the ambient `claude login`
  /// OAuth session (see `defaultClaudeRunner`'s session-isolation comment
  /// in pipeline_executor.dart), setting this breaks any step for a user
  /// without `ANTHROPIC_API_KEY` set — not a hypothetical, reproduced
  /// directly. No built-in pipeline step uses [StepMode.bare] — only
  /// tests exercising the mechanism itself (e.g.
  /// pipeline_executor_test.dart) do.
  final StepMode mode;

  /// Tools the spawned process may use. Defaults to [ToolGrant.readOnly] —
  /// every step's edits are parsed from its output and applied by the
  /// caller, so no step needs write or execute tools yet.
  final ToolGrant toolGrant;

  const AgentStep({
    required this.id,
    required this.label,
    required this.model,
    required this.systemPrompt,
    required this.buildPrompt,
    this.modelSelector,
    this.routes = const {},
    this.postProcess,
    this.mode = StepMode.project,
    this.toolGrant = ToolGrant.readOnly,
  });

  /// Resolves the model the executor should invoke for this step given
  /// [ctx]. Honors [modelSelector] when present; otherwise returns
  /// [model]. The `??` here only fires for "no selector wired" — the
  /// selector itself is total and cannot return null (see typedef).
  AgentModel effectiveModel(PipelineContext ctx) =>
      modelSelector?.call(ctx) ?? model;
}
