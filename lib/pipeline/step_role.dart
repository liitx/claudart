// step_role.dart — the job a pipeline step does, and which models may do it.
//
// Every AgentStep declares exactly one role. The role decides which models the
// step may run on, so a step cannot be wired to a model that is not sufficient
// for its job. Haiku is the cheapest model and is not sufficient to reason or
// implement: it may only classify and read.

import 'agent_model.dart';

/// The job a pipeline step does.
///
/// Partition: classification, fileReading, reasoning and implementation are
/// disjoint and together cover every step the pipeline defines. Adding a role
/// without deciding its permitted models is a compile error in
/// [permittedModels].
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
