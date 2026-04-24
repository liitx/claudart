// claudart_surface.dart — named render-surface type for the pipeline engine
//
// Formalises the two surfaces the pipeline runs on:
//   cli — stdout/ANSI/spinner; default injectables (stdin prompter, arrowMenu)
//   tui — nocterm stream; Completer-based bridges required, no stdout side-effects
//
// Usage:
//   CLI command:  SurfaceExecutorConfig.cli().build()
//   TUI screen:   SurfaceExecutorConfig.tui(prompter: …, approvalSelector: …).build()
//
// The .tui() constructor requires both bridges — TUI must never fall back to
// stdin (it doesn't exist in a nocterm context), so the compiler enforces this.

import 'pipeline_executor.dart';

enum ClaudartSurface {
  cli(label: 'CLI', usesStdout: true),
  tui(label: 'TUI', usesStdout: false);

  const ClaudartSurface({required this.label, required this.usesStdout});

  final String label;
  final bool   usesStdout;
}

// ── SurfaceExecutorConfig ─────────────────────────────────────────────────────
//
// Typed factory for PipelineExecutor. Carries the surface declaration so the
// executor's origin is queryable; enforces required bridges per surface.

class SurfaceExecutorConfig {
  SurfaceExecutorConfig.cli({
    ClaudeRunner? runner,
    bool          strict = false,
  })  : surface           = ClaudartSurface.cli,
        _runner           = runner,
        _prompter         = null,
        _approvalSelector = null,
        _strict           = strict;

  /// [approvalSelector] is required only when pipeline steps contain an
  /// [ApprovalGate] route. Screens that manage approval externally (e.g.
  /// SuggestScreen, where the gate is in the screen state machine) may omit it.
  SurfaceExecutorConfig.tui({
    required UserPrompter     prompter,
    ApprovalSelector?         approvalSelector,
    ClaudeRunner?             runner,
    bool                      strict = false,
  })  : surface           = ClaudartSurface.tui,
        _runner           = runner,
        _prompter         = prompter,
        _approvalSelector = approvalSelector,
        _strict           = strict;

  final ClaudartSurface   surface;
  final ClaudeRunner?     _runner;
  final UserPrompter?     _prompter;
  final ApprovalSelector? _approvalSelector;
  final bool              _strict;

  PipelineExecutor build() => PipelineExecutor(
        runner:           _runner,
        prompter:         _prompter,
        approvalSelector: _approvalSelector,
        strict:           _strict,
      );
}
