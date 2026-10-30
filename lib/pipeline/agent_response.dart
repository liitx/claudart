// agent_response.dart — the typed surface every agent/subagent emission takes.
//
// Design: docs/agent_response_and_output.md.
//
// `AgentResponse` is a sealed hierarchy (mirrors `StepRoute` in step_route.dart):
// one final class per emission kind, each carrying a `Speaker`, a `kind`, and a
// `hue`. `ResponseKind` owns the kind's label + glyph; the COLOUR comes from the
// `hue` — a `StateHue`, the single cross-package source of state colour
// semantics ("shape stays constant, colour shifts"). The render layer
// (lib/ui/render.dart) maps the hue to ANSI and colours the block's header +
// gutter, never the body.
//
// Additive and separate from `PipelineEvent` (pipeline_event.dart): that is the
// executor's internal lifecycle stream; AgentResponse is the user-facing typed
// output the render layer formats.
//
// Update (2026-09-27): StateHue relocated here from zedup — this field was
// claudart's only reason to depend on zedup as a real runtime dependency.
// zedup still owns the nocterm-rendering half (a StateHueRendering
// extension with .color/.tickDuration) and re-exports this enum.

import 'agent_flow.dart';
import 'state_hue.dart';

/// Who is speaking. Rendered as a lane label; colour comes from the response's
/// [AgentResponse.hue] (state), not the speaker — identity is the label axis,
/// state is the colour axis.
enum Speaker {
  claudart,
  agent,
  subagent;

  String get label => switch (this) {
        Speaker.claudart => 'claudart',
        Speaker.agent    => 'agent',
        Speaker.subagent => 'subagent',
      };
}

/// Lifecycle state of a single subtask. `awaitingAnswer` makes the never-guess
/// rule enforceable (see [Result.forSubtask]); `failed` carries the error hue.
enum SubtaskState {
  ready,
  blocked,
  awaitingAnswer,
  running,
  done,
  failed;

  /// The shared state colour for this subtask, via [StateHue] so the Plan's
  /// colour-coded titles match every other state surface (zedup's rendering
  /// of this same enum, via its own StateHueRendering extension).
  StateHue get hue => switch (this) {
        SubtaskState.ready          => StateHue.ready,
        SubtaskState.blocked        => StateHue.inactive,
        SubtaskState.awaitingAnswer => StateHue.paused,
        SubtaskState.running        => StateHue.active,
        SubtaskState.done           => StateHue.success,
        SubtaskState.failed         => StateHue.error,
      };
}

/// One unit of work inside the agent's plan. Priority and `dependsOn` drive
/// ordering and unblock detection; `state` drives the colour of its Plan title.
class Subtask {
  final String id;
  final String workspace;
  final int priority;
  final List<String> dependsOn;
  final SubtaskState state;

  const Subtask({
    required this.id,
    required this.workspace,
    required this.priority,
    this.dependsOn = const [],
    this.state = SubtaskState.ready,
  });

  /// A subtask blocked on a question neither the agent nor a peer could
  /// resolve. While true, the subtask may only produce a [Question].
  bool get hasUnresolvedQuestion => state == SubtaskState.awaitingAnswer;
}

/// A concrete code action a subagent took. Surfacing these is how the user sees
/// what the agent is doing with the code (and spots two subagents touching the
/// same file).
enum ActionVerb {
  created('+'),
  edited('~'),
  deleted('-'),
  ran('▶'),
  read('·');

  const ActionVerb(this.glyph);

  /// Short, fixed glyph shown before the target.
  final String glyph;
}

/// Raised when code tries to produce a [Result] for a subtask that still has an
/// unresolved question. Encodes the never-guess rule structurally.
const String neverGuessViolation =
    'never-guess: a subtask with an unresolved question may emit only a '
    'Question, never a Result';

/// The response kinds. Owns label, glyph, and sort priority. `sortPriority`
/// ascends in render order — Question is 0 so questions always float to the top
/// regardless of arrival order. Colour is NOT here — it comes from the hue.
enum ResponseKind {
  question(label: 'Question', icon: '?', sortPriority: 0),
  blocker(label: 'Blocker', icon: '✗', sortPriority: 1),
  replan(label: 'Replan', icon: '⟳', sortPriority: 2),
  plan(label: 'Plan', icon: '◆', sortPriority: 3),
  progress(label: 'Progress', icon: '•', sortPriority: 4),
  action(label: 'Action', icon: '▸', sortPriority: 5),
  result(label: 'Result', icon: '✓', sortPriority: 6),
  handoff(label: 'Handoff', icon: '→', sortPriority: 7);

  const ResponseKind({
    required this.label,
    required this.icon,
    required this.sortPriority,
  });

  final String label;
  final String icon;
  final int sortPriority;
}

/// Every agent/subagent emission is one of these. The render layer is the only
/// consumer and switches exhaustively on the subtype. `hue` is the state colour
/// the renderer applies to the header + gutter.
sealed class AgentResponse {
  final Speaker speaker;
  const AgentResponse(this.speaker);

  ResponseKind get kind;
  StateHue get hue;
}

/// An emission about one subtask in one workspace — the shared shape of
/// [Progress], [Action] and [Result].
sealed class SubtaskResponse extends AgentResponse {
  final String workspace;
  final String subtask;

  const SubtaskResponse(super.speaker,
      {required this.workspace, required this.subtask});
}

/// Goal + priority-ordered subtasks across workspaces.
final class Plan extends AgentResponse {
  final String goal;
  final List<Subtask> subtasks;

  const Plan({required Speaker speaker, required this.goal, required this.subtasks})
      : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.plan;

  @override
  StateHue get hue => StateHue.ready;
}

/// Where a subtask is in its flow, and whether it is blocked.
final class Progress extends SubtaskResponse {
  final AgentFlow flow;
  final bool blocked;

  const Progress({
    required Speaker speaker,
    required super.workspace,
    required super.subtask,
    required this.flow,
    required this.blocked,
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.progress;

  @override
  StateHue get hue => blocked ? StateHue.paused : StateHue.active;
}

/// A question escalated to the user because nobody could resolve it. The only
/// emission a subtask with an unresolved question is allowed to make.
final class Question extends AgentResponse {
  final String origin;
  final String workspace;
  final String blockedSubtask;
  final String question;
  final List<String> options;

  const Question({
    required Speaker speaker,
    required this.origin,
    required this.workspace,
    required this.blockedSubtask,
    required this.question,
    this.options = const [],
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.question;

  @override
  StateHue get hue => StateHue.paused;
}

/// A concrete code action by a subagent — created/edited/ran something, with a
/// one-line note on what it does.
final class Action extends SubtaskResponse {
  final ActionVerb verb;
  final String target;
  final String summary;

  const Action({
    required Speaker speaker,
    required super.workspace,
    required super.subtask,
    required this.verb,
    required this.target,
    this.summary = '',
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.action;

  @override
  StateHue get hue => StateHue.active;
}

/// A completed subtask artifact.
final class Result extends SubtaskResponse {
  final List<String> filesTouched;
  final String summary;

  const Result({
    required Speaker speaker,
    required super.workspace,
    required super.subtask,
    required this.filesTouched,
    required this.summary,
  }) : super(speaker);

  /// Guarded constructor enforcing never-guess: throws [StateError] when the
  /// subtask still has an unresolved question, so a guessed result is
  /// impossible to construct.
  factory Result.forSubtask(
    Subtask subtask, {
    required Speaker speaker,
    required List<String> filesTouched,
    required String summary,
  }) {
    if (subtask.hasUnresolvedQuestion) {
      throw StateError(neverGuessViolation);
    }
    return Result(
      speaker:      speaker,
      workspace:    subtask.workspace,
      subtask:      subtask.id,
      filesTouched: filesTouched,
      summary:      summary,
    );
  }

  @override
  ResponseKind get kind => ResponseKind.result;

  @override
  StateHue get hue => StateHue.success;
}

/// A failure inside a subtask.
final class Blocker extends AgentResponse {
  final String workspace;
  final String step;
  final String errorType;

  const Blocker({
    required Speaker speaker,
    required this.workspace,
    required this.step,
    required this.errorType,
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.blocker;

  @override
  StateHue get hue => StateHue.error;
}

/// The agent resolved a question and passed the answer to a blocked subagent.
final class Handoff extends AgentResponse {
  final String from;
  final String to;
  final String resolvedInfo;

  const Handoff({
    required Speaker speaker,
    required this.from,
    required this.to,
    required this.resolvedInfo,
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.handoff;

  @override
  StateHue get hue => StateHue.ready;
}

/// Priorities changed in response to an answer. Carries the old and new order
/// so the render layer can show the diff.
final class Replan extends AgentResponse {
  final String reason;
  final List<String> oldOrder;
  final List<String> newOrder;

  const Replan({
    required Speaker speaker,
    required this.reason,
    required this.oldOrder,
    required this.newOrder,
  }) : super(speaker);

  @override
  ResponseKind get kind => ResponseKind.replan;

  @override
  StateHue get hue => StateHue.active;
}

/// Orders responses for rendering: ascending [ResponseKind.sortPriority], so
/// Questions float to the top. Stable within a kind (preserves arrival order).
List<AgentResponse> floatQuestions(Iterable<AgentResponse> responses) {
  final indexed = responses.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final byKind = a.value.kind.sortPriority.compareTo(b.value.kind.sortPriority);
    return byKind != 0 ? byKind : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}
