// fake_executors.dart — pipeline executors for tests that must not start the
// real model.

import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';

import 'unscripted.dart';

/// An executor whose model never answers: every step fails as if the model gave
/// no result, and no real process is started.
PipelineExecutor noModelExecutor() => PipelineExecutor(
      prompter: unscriptedUserPrompter,
      approvalSelector: unscriptedApprovalSelector,
      runner: ({
        required model,
        required systemPrompt,
        required message,
        required workingDir,
        required allowedTools,
        required helperModel,
        StepMode mode = StepMode.project,
      }) async =>
          null,
    );
