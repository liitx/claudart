# Changelog

## Unreleased

Workflow gap fixes; see `docs/workflow_gaps.md` for the full audit and the
open questions.

- **Fixed:** `/dev/null` was treated as a terminal on macOS, so `init`, `link`,
  `setup`, `kill`, `flow`, the launcher and `suggest` crashed with an unhandled
  `StdinException` (errno 19) when stdin was closed, leaving the terminal cursor
  hidden. New
  `canUseRawTerminal()` falls back to line-based input.
- **Fixed (safety):** end of input at a numbered menu used to select the first
  option, which in the debug/suggest review menus means "apply (write all files
  to disk)". It now aborts with a message and exit code 1. **Behaviour change:**
  any menu reached with closed stdin now exits 1 instead of taking option 1.
- **Fixed:** `debug` rejected the scope list `suggest` had just written
  ("No files listed in Scope") whenever the model did not backtick a relative
  path. `parseScopeFiles` now accepts the common bullet shapes and absolute
  paths inside the project (including through a symlinked root); absolute
  paths outside the project are dropped.

## 2.0.0

**Breaking:** `ClaudeRunner` (exported via `pipeline_executor.dart`) gained a
`mode` named parameter (`StepMode`). Any code constructing
`PipelineExecutor(runner: ...)` with a function literal that doesn't declare
`mode` will fail to type-check; add `StepMode mode = StepMode.project` to
the closure's parameter list. No compatibility adapter provided —
`ClaudeRunner` has no known external consumers (no pub.dev publish, no
other package in this workspace imports it; zedup has an unrelated
same-named local type).

- `AgentStep` gained `postProcess` (rewrite a step's output before it's
  stored/routed on) and `mode` (`StepMode.bare` passes `--bare` to the
  claude CLI subprocess — no built-in step uses it; see the doc comment on
  the field for why not).
- `PipelineExecutor` applies `postProcess` before routing and wires `mode`
  through to `ClaudeRunner`.
- `flow`'s plan/construct steps inject a project directory/enum index so
  generated handoffs can't reference paths or types that don't exist.
- `suggest`'s applier step now sends/receives only the analysis sections a
  change plan targets, merged back into the full document, instead of
  round-tripping all six sections every refinement pass.

## 1.0.0

Initial release.

- `claudart` interactive launcher — lists workspace projects, routes into setup workflow
- `claudart init` — scaffolds workspace with generic Dart/Flutter/BLoC/Riverpod/testing knowledge
- `claudart init --project <name>` — creates project-specific knowledge file
- `claudart link` — symlinks workspace into project, reads `pubspec.yaml` to embed SDK constraints in `CLAUDE.md`
- `claudart unlink` — removes workspace symlinks cleanly
- `claudart setup` — prompts for bug context, writes `handoff.md`
- `claudart status` — prints active handoff state
- `claudart teardown` — classifies session learnings, archives handoff, suggests commit message
- `FileIO` and `ProcessRunner` interfaces for testable I/O injection
- `MemoryFileIO` and `mocktail`-based mocks for unit testing without disk access
