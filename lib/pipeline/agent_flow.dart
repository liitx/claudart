// agent_flow.dart — enhanced enum of all agent pipeline variants
//
// AgentFlow is the single source of truth for:
//   - which model is preferred for a given workflow
//   - which steps constitute that workflow
//   - the slash command .md template installed by `claudart link`
//
// Adding a new flow forces all exhaustive switches to update — the compiler
// enforces coverage across the codebase.
//
// Canonical across repos:
//   claudart — pipeline engine (suggest, debug, setup, save, teardown, flow, research, free)
//   zedup    — consumer; adds AgentFlowZed extension for TUI-layer behaviour (label, isCli)
//              cli variant covers slash commands that shell out with no API call

import '../commands/debug_template.dart';
import '../commands/flow_template.dart';
import '../commands/save_template.dart';
import '../commands/setup_template.dart';
import '../commands/suggest_template.dart';
import '../commands/teardown_template.dart';
import 'agent_model.dart';
import 'agent_step.dart';
import 'flows/debug_steps.dart';
import 'flows/save_steps.dart';
import 'flows/setup_steps.dart';

enum AgentFlow {
  /// Deep exploration + knowledge transfer — root cause, scope, constraints.
  /// preferredModel: opus — deepest reasoning for root-cause exploration.
  /// Pipeline steps use their own model choices (haiku reader, sonnet reasoner).
  /// Steps are built dynamically via SuggestSteps.phases(fileCount) in suggest.dart.
  suggest(
    preferredModel:  AgentModel.opus,
    steps:           [],
    hasCommandFile:  true,
  ),

  /// Deterministic scoped implementation — minimal diff, no exploration.
  debug(
    preferredModel:  AgentModel.sonnet,
    steps:           DebugSteps.all,
    hasCommandFile:  true,
  ),

  /// Session setup — workspace init, handoff scaffold.
  setup(
    preferredModel:  AgentModel.haiku,
    steps:           SetupSteps.all,
    hasCommandFile:  true,
  ),

  /// Checkpoint session — snapshot handoff, deposit facts to skills.
  save(
    preferredModel:  AgentModel.haiku,
    steps:           SaveSteps.all,
    hasCommandFile:  true,
  ),

  /// Session teardown — close workspace, update project README.
  teardown(
    preferredModel:  AgentModel.haiku,
    steps:           [],
    hasCommandFile:  true,
  ),

  /// Agent-constructed session — user provides freeform prompt; agents
  /// classify, plan, get approval, and construct the handoff automatically.
  /// Experimental variant of suggest.
  flow(
    preferredModel:  AgentModel.sonnet,
    steps:           [],   // steps accessed via FlowSteps.* directly in flow.dart
    hasCommandFile:  true,
  ),

  /// Constrained single-doc lookup — fast, targeted reference answer.
  research(
    preferredModel:  AgentModel.haiku,
    steps:           [],
    hasCommandFile:  false,
  ),

  /// Conversational — no context injection, balanced default.
  free(
    preferredModel:  AgentModel.sonnet,
    steps:           [],
    hasCommandFile:  false,
  ),

  /// CLI shell-out — no API call, no pipeline steps.
  /// Used by zedup for slash commands that delegate to claudart CLI directly
  /// (e.g. /save, /status, /teardown). preferredModel is null.
  cli(
    preferredModel:  null,
    steps:           [],
    hasCommandFile:  false,
  );

  const AgentFlow({
    required this.preferredModel,
    required List<AgentStep> steps,
    required this.hasCommandFile,
  }) : _steps = steps;

  /// The model best suited for this flow's primary task.
  /// Null for [cli] — no API call is made.
  final AgentModel? preferredModel;

  final List<AgentStep> _steps;

  /// Whether this flow installs a slash command .md file via `claudart link`.
  final bool hasCommandFile;

  /// The default step list for this flow.
  /// For suggest, prefer [SuggestSteps.phases(fileCount)] to get the dynamic label.
  List<AgentStep> get steps => _steps;

  /// The claudart CLI args for this flow: `['claudart', name]`.
  /// Consumers (e.g. zedup) use this to shell out for session-lifecycle flows
  /// (save, setup, teardown) without hardcoding command strings at call sites.
  List<String> get cliArgs => ['claudart', name];

  // ── Workspace / command file ──────────────────────────────────────────────────

  /// Filename written to `.claude/commands/` by `claudart link`.
  String get fileName => '$name.md';

  /// Generates the slash command template content for this flow.
  ///
  /// [projectName] is interpolated into the YAML frontmatter so picker UIs
  /// (Zed claude-acp, Cursor, Claude Code) can label commands per workspace.
  ///
  /// ∀ v ∈ AgentFlow.values where v.hasCommandFile → v.commandTemplate(w, n).isNotEmpty
  /// Enforced by the exhaustive switch — adding a variant without a template arm
  /// is a compile error.
  String commandTemplate(String workspacePath, String projectName) => switch (this) {
        AgentFlow.suggest  => suggestCommandTemplate(workspacePath, projectName),
        AgentFlow.debug    => debugCommandTemplate(workspacePath, projectName),
        AgentFlow.setup    => setupCommandTemplate(workspacePath, projectName),
        AgentFlow.save     => saveCommandTemplate(workspacePath, projectName),
        AgentFlow.teardown => teardownCommandTemplate(workspacePath, projectName),
        AgentFlow.flow     => flowCommandTemplate(workspacePath, projectName),
        AgentFlow.research => '',
        AgentFlow.free     => '',
        AgentFlow.cli      => '',
      };

  // ── Serialisation ────────────────────────────────────────────────────────────

  String get value => name;

  static AgentFlow? fromString(String s) =>
      AgentFlow.values.where((v) => v.name == s).firstOrNull;

  // ── Slash command → AgentFlow mapping ────────────────────────────────────────

  /// Maps a slash command string (e.g. '/suggest') to an [AgentFlow].
  /// Returns null for unrecognised commands.
  static AgentFlow? fromSlashCommand(String cmd) => switch (cmd) {
        '/suggest'  => AgentFlow.suggest,
        '/debug'    => AgentFlow.debug,
        '/setup'    => AgentFlow.setup,
        '/save'     => AgentFlow.save,
        '/teardown' => AgentFlow.teardown,
        '/flow'     => AgentFlow.flow,
        '/research' => AgentFlow.research,
        _           => null,
      };
}
