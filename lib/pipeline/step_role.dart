// step_role.dart — the job a pipeline step does, which models may do it and
// which tools it may use.
//
// Every AgentStep declares exactly one role. The role decides which models the
// step may run on, so a step cannot be wired to a model that is not sufficient
// for its job. Haiku is the cheapest model and is not sufficient to reason or
// implement: it may only classify and read. The role also decides which tools
// the step may use, so a read-only role is read-only.

import 'agent_model.dart';

/// A built-in tool of the `claude` CLI that a step may be allowed to use.
enum ClaudeTool {
  /// Reads a file.
  read('Read'),

  /// Finds files by name pattern.
  glob('Glob'),

  /// Searches file contents.
  grep('Grep');

  const ClaudeTool(this.wire);

  /// The name the `claude` CLI expects in its `--tools` list.
  final String wire;
}

/// A process setting that names the model the `claude` CLI uses for its own
/// small helper calls inside a step, which default to haiku.
enum ClaudeHelperModelVariable {
  /// The model behind the CLI's `haiku` alias, which its helper calls use.
  defaultHaikuModel('ANTHROPIC_DEFAULT_HAIKU_MODEL'),

  /// The model the CLI uses for fast, small requests (the older name for the
  /// same setting).
  smallFastModel('ANTHROPIC_SMALL_FAST_MODEL');

  const ClaudeHelperModelVariable(this.wire);

  /// The environment variable name the `claude` CLI reads.
  final String wire;
}

/// The tools that only read: no tool here can write a file or run a command.
const Set<ClaudeTool> readOnlyTools = {
  ClaudeTool.read,
  ClaudeTool.glob,
  ClaudeTool.grep,
};

/// The job a pipeline step does.
///
/// Partition: classification, fileReading, reasoning and implementation are
/// disjoint and together cover every step the pipeline defines. Adding a role
/// without deciding its permitted models or its allowed tools is a compile
/// error in [permittedModels] and [allowedTools].
enum StepRole {
  /// Labels a task from its description (the categorize step). Produces a few
  /// tags and no analysis.
  classification,

  /// Reads the listed files and returns their contents without interpreting
  /// them (the reader steps).
  fileReading,

  /// Draws conclusions: plans, analyzes, answers questions from findings,
  /// resolves ambiguity.
  reasoning,

  /// Produces or edits code, documents or other deliverables.
  implementation;

  /// The models allowed to run a step of this role.
  ///
  /// Classification and file reading are minor tasks, so any model may do
  /// them. Reasoning and implementation require sonnet or opus; haiku is never
  /// permitted for them.
  Set<AgentModel> get permittedModels => switch (this) {
        StepRole.classification ||
        StepRole.fileReading =>
          {
            AgentModel.haiku,
            AgentModel.sonnet,
            AgentModel.opus,
            AgentModel.fable,
          },
        StepRole.reasoning ||
        StepRole.implementation =>
          {AgentModel.sonnet, AgentModel.opus},
      };

  /// The tools a step of this role may use.
  ///
  /// Classification needs no tool: it labels from the prompt alone. File
  /// reading, reasoning and implementation may only read. Implementation
  /// returns its plan as output and writes nothing to disk; the owner approves
  /// the write, which the pipeline performs itself.
  Set<ClaudeTool> get allowedTools => switch (this) {
        StepRole.classification => const {},
        StepRole.fileReading ||
        StepRole.reasoning ||
        StepRole.implementation =>
          readOnlyTools,
      };

  /// The model the `claude` CLI uses for its own helper calls inside a step of
  /// this role. Classification and file reading are minor tasks, so haiku is
  /// fine there; reasoning and implementation never show haiku, so the helper
  /// calls run on sonnet, which every such role permits.
  AgentModel get helperModel => switch (this) {
        StepRole.classification ||
        StepRole.fileReading =>
          AgentModel.haiku,
        StepRole.reasoning ||
        StepRole.implementation =>
          AgentModel.sonnet,
      };

  /// Whether a step of this role may run on [model].
  bool permits(AgentModel model) => permittedModels.contains(model);
}

/// The fields recorded in the context of a failure raised when a step is wired
/// to a model its [StepRole] does not permit. The enum name is the key.
enum StepRoleViolationField {
  /// The [StepRole] of the step.
  role,

  /// The [AgentModel] that was chosen and is not permitted.
  model,
}
