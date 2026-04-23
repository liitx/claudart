// step_route.dart — sealed routing instructions for pipeline steps
//
// Every AgentStep declares a routes map: tag → StepRoute.
// The executor switches on the StepRoute to determine what to do next.
// The sealed hierarchy ensures exhaustive switch coverage at compile time.
//
// Routing model:
//   GoTo           → jump to a named step by id
//   QuestionBranch → delegate to a lookup step to answer a question
//   FeedBackTo     → store lookup answer in ctx, return to a named step
//   EscalateUser   → lookup couldn't answer; ask the user, return to named step
//   Complete       → terminal — return the current context

/// Routing instruction emitted when an XML tag matches in step output.
sealed class StepRoute {
  const StepRoute();
}

/// Jump unconditionally to the step with [stepId].
final class GoTo extends StepRoute {
  final String stepId;
  const GoTo(this.stepId);
}

/// The current step emitted a `<QUESTION>` — delegate to [lookupStepId]
/// before re-running this step. The executor saves the return target.
final class QuestionBranch extends StepRoute {
  final String lookupStepId;
  const QuestionBranch(this.lookupStepId);
}

/// Lookup answered the question — store the answer in ctx and return to [stepId].
final class FeedBackTo extends StepRoute {
  final String stepId;
  const FeedBackTo(this.stepId);
}

/// Lookup could not answer — ask the user, store their answer, return to [returnToStepId].
final class EscalateUser extends StepRoute {
  final String returnToStepId;
  const EscalateUser(this.returnToStepId);
}

/// The plan step produced a draft — yield PlanDraft + AwaitingApproval,
/// wait for user approval, then continue to [nextStepId] on confirm.
/// Aborts (yields PipelineCompleted) if the user declines.
final class ApprovalGate extends StepRoute {
  final String planTag;     // XML tag in step output containing the plan text
  final String nextStepId;  // step to run after approval
  const ApprovalGate({required this.planTag, required this.nextStepId});
}

/// Terminal route — the pipeline is complete, return ctx.
final class Complete extends StepRoute {
  const Complete();
}
