// agent_flow.dart — enhanced enum of all agent pipeline variants
//
// AgentFlow is the single source of truth for:
//   - which steps constitute a given workflow (and so which roles and
//     models each flow uses, through each step's StepRole)
//   - the slash command .md template installed by `claudart link`
//   - which slash commands map to which flow
//
// Adding a new flow forces all exhaustive switches to update — the compiler
// enforces coverage across the codebase.
//
// Canonical across repos:
//   claudart — pipeline engine (suggest, debug, setup, save, teardown, flow, research, free)
//   zedup    — consumer; adds AgentFlowZed extension for TUI-layer behaviour (label, isCli)
//              cli variant covers slash commands that shell out with no API call

import '../templates/debug_template.dart';
import '../templates/flow_template.dart';
import '../templates/save_template.dart';
import '../templates/setup_template.dart';
import '../templates/suggest_template.dart';
import '../templates/teardown_template.dart';
import '../util/enum_util.dart';
import 'agent_step.dart';
import 'flows/debug_steps.dart';
import 'flows/flow_steps.dart';
import 'flows/save_steps.dart';
import 'flows/setup_steps.dart';
import 'flows/suggest_steps.dart';
import 'flows/teardown_steps.dart';

/// File count and refinement pass used to build the representative step
/// list for flows whose steps are built dynamically (their labels depend
/// on the run's file count or pass number; role and model do not).
const int _representativeCount = 1;

/// Prefix every slash command carries before its flow name.
const String _slashPrefix = '/';

enum AgentFlow {
  /// Deep exploration + knowledge transfer — root cause, scope, constraints.
  /// Steps are built dynamically in suggest.dart; [steps] lists them all.
  suggest(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Deterministic scoped implementation — minimal diff, no exploration.
  debug(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Session setup — workspace init, handoff scaffold.
  setup(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Checkpoint session — snapshot handoff, deposit facts to skills.
  save(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Session teardown — close workspace, update project README.
  teardown(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Agent-constructed session — user provides freeform prompt; agents
  /// classify, plan, get approval, and construct the handoff automatically.
  /// Experimental variant of suggest.
  flow(
    hasCommandFile: true,
    hasSlashCommand: true,
  ),

  /// Constrained single-doc lookup — fast, targeted reference answer.
  research(
    hasCommandFile: false,
    hasSlashCommand: true,
  ),

  /// Conversational — no context injection, balanced default.
  free(
    hasCommandFile: false,
    hasSlashCommand: false,
  ),

  /// CLI shell-out — no API call, no pipeline steps.
  /// Used by zedup for slash commands that delegate to claudart CLI directly
  /// (e.g. /save, /status, /teardown).
  cli(
    hasCommandFile: false,
    hasSlashCommand: false,
  ),

  /// Visual design review + spec generation. Routed by the planner when
  /// the scoped paths classify as design surfaces (widgets/painters/theme).
  guiDesign(
    hasCommandFile: false,
    hasSlashCommand: false,
  );

  const AgentFlow({
    required this.hasCommandFile,
    required this.hasSlashCommand,
  });

  /// Whether this flow installs a slash command .md file via `claudart link`.
  final bool hasCommandFile;

  /// Whether `/<name>` is a recognized slash command for this flow.
  final bool hasSlashCommand;

  /// Every step this flow runs, in order, dynamic steps included. Steps
  /// whose label depends on a file count or pass number are built with a
  /// representative value; their role and model are the same for any value.
  /// Empty for flows that run no pipeline steps.
  ///
  /// Enforced by the exhaustive switch — adding a variant without an arm is
  /// a compile error.
  List<AgentStep> get steps => switch (this) {
        AgentFlow.suggest  => [
            FlowSteps.categorize,
            ...SuggestSteps.phases(_representativeCount),
            ...SuggestSteps.refinement(_representativeCount),
          ],
        AgentFlow.debug    => [
            FlowSteps.categorize,
            ...DebugSteps.forScope(_representativeCount),
          ],
        AgentFlow.setup    => SetupSteps.all,
        AgentFlow.save     => SaveSteps.all,
        AgentFlow.teardown => [TeardownSteps.analyzer],
        AgentFlow.flow     => [
            FlowSteps.categorize,
            FlowSteps.plan,
            FlowSteps.clarify,
            FlowSteps.construct,
          ],
        AgentFlow.research ||
        AgentFlow.free ||
        AgentFlow.cli ||
        AgentFlow.guiDesign =>
          const [],
      };

  /// The claudart CLI args for this flow: `['claudart', name]`.
  /// Consumers (e.g. zedup) use this to shell out for session-lifecycle flows
  /// (save, setup, teardown) without hardcoding command strings at call sites.
  List<String> get cliArgs => ['claudart', name];

  // ── Workspace / command file ──────────────────────────────────────────────────

  /// Filename written to `.claude/commands/` by `claudart link`.
  /// Suffixed with the project name so picker UIs can distinguish per-workspace.
  String fileName(String projectName) => '$name-$projectName.md';

  /// Old un-suffixed name — deleted on re-link to clear stale duplicates.
  String get legacyFileName => '$name.md';

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
        AgentFlow.research ||
        AgentFlow.free ||
        AgentFlow.cli ||
        AgentFlow.guiDesign =>
          '',
      };

  // ── Serialisation ────────────────────────────────────────────────────────────

  String get value => name;

  static AgentFlow? fromString(String s) => enumByName(AgentFlow.values, s);

  // ── Slash command → AgentFlow mapping ────────────────────────────────────────

  /// Maps a slash command string (e.g. '/suggest') to an [AgentFlow] by
  /// deriving `/<name>` from each flow whose [hasSlashCommand] is true.
  /// Returns null for unrecognised commands.
  static AgentFlow? fromSlashCommand(String cmd) {
    for (final flow in AgentFlow.values) {
      if (flow.hasSlashCommand && cmd == '$_slashPrefix${flow.name}') {
        return flow;
      }
    }
    return null;
  }
}
