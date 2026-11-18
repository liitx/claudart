// step_status.dart — UI-facing lifecycle state of a single pipeline step
//
// Not produced by PipelineExecutor directly — the executor's real
// lifecycle model is the sealed PipelineEvent hierarchy (pipeline_event.dart).
// StepStatus is a derived projection of that stream for consumers that want
// a per-step display state (spinner glyph, colour) rather than the full
// event. `StepStatusFromEvent.fromEvent` is the one canonical, tested
// projection — consumers should use it instead of re-deriving their own
// mapping. (Called via the extension's own name, not `StepStatus.fromEvent`
// — a static extension member is namespaced under the extension, not the
// extended type.)
//
// `waiting` added 2026-09-27: AgentEscalating/AgentResumed now carry a
// stepId (previously session-level events with no per-step identity), so
// they drive a real status transition instead of leaving the active
// step's displayed status untouched. Five events identify a single step
// now, not three.
//
// `.hue`/`.glyph` added 2026-09-27: 3 zedup render files each hand-wrote
// an identical StepStatus → (glyph, colour) switch. `.hue` returns a
// StateHue (this repo's own — see state_hue.dart), not a raw colour, so
// this file still never needs nocterm; zedup's StateHueRendering
// extension turns any StateHue into a concrete Color.

import 'pipeline_event.dart';
import 'state_hue.dart';

enum StepStatus {
  pending(hue: StateHue.inactive, glyph: '○'),
  running(hue: StateHue.active, glyph: '◉'),

  /// `waiting` maps to [StateHue.paused] deliberately: that hue's own
  /// definition ("paused intentionally — waiting on user input") is an
  /// exact match for what this status means.
  waiting(hue: StateHue.paused, glyph: '◉'),
  done(hue: StateHue.success, glyph: '✓'),
  failed(hue: StateHue.error, glyph: '✗');

  const StepStatus({required this.hue, required this.glyph});

  /// Shared state-semantic colour category — see [StateHue] and zedup's
  /// `StateHueRendering` extension for the concrete rendered colour.
  final StateHue hue;

  /// The single-character glyph rendered alongside this status.
  final String glyph;
}

extension StepStatusFromEvent on StepStatus {
  /// Projects a [PipelineEvent] onto a [StepStatus], or `null` when the
  /// event carries no per-step status change of its own — the caller
  /// should keep whatever status it already had. Only events that
  /// identify a single step (`stepId`) drive a status transition; the
  /// flow-command approval gate and pipeline completion are session-level
  /// and leave the active step's displayed status untouched.
  static StepStatus? fromEvent(PipelineEvent event) => switch (event) {
        AgentStarted() || AgentResumed() => StepStatus.running,
        AgentCompleted() => StepStatus.done,
        AgentFailed() => StepStatus.failed,
        AgentEscalating() => StepStatus.waiting,
        PlanDraft() ||
        AwaitingApproval() ||
        PipelineCompleted() =>
          null,
      };
}
