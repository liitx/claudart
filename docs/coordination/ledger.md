# Coordination ledger — 2026-10-12

Source: three read-only Opus audits (claudart, dartrix, zedup) plus coordinator spot-checks.
`[V]` = verified by the coordinator against code. `[A]` = audit claim, not yet re-checked.
Session: claudart coordinator handoff (`handoff.md`, status suggest-investigating).

## Where we are

- claudart: v1 and v2 shipped. Phase 1 steps 4-7 merged. Local branch `feat/mutation-runner-streams` (2 commits, not pushed) holds the stream-based mutation runner.
- dartrix: small library, analyzes clean; much of what PARADIGMS.md promises is not code yet.
- zedup: consumes claudart 33 commits behind main; duplicates claudart concepts.

## A. The state machine is documented, not enforced (claudart)  — highest priority

| # | Finding | Evidence |
|---|---|---|
| A1 | `docs/design.md:62` says δ is compiler-exhaustive. No transition function exists; status writes are bare strings. [V] | `lib/md_io.dart:36`, `commands/suggest.dart:248`, `commands/debug.dart:206` |
| A2 | `debug-in-progress` is never written by any command. `debug-complete` is written before any verification. [V for write sites] | `commands/debug.dart:206` |
| A3 | `claudart flow` writes `ready-for-suggest`, absent from the δ table. [A] | `pipeline/flows/flow_steps.dart:68` |
| A4 | Debug precondition defined twice and disagrees: `debug.dart` accepts only ready-for-debug, `sync_check.dart:121` also accepts debugInProgress. [A] | |
| A5 | `suggest.dart:69` compares status as a string against `'debug-in-progress'`. [V] | |
| A6 | `expectsSuggest`/`expectsDebug` have zero callers in lib/bin. [V] | `session/session_state.dart:48,60` |

## B. Tests that cannot fail meaningfully

| # | Finding | Evidence |
|---|---|---|
| B1 | Only 2 of 8 `HandoffStatus` variants are ever covered; `assertNoGaps` checks only touched variants, so the rest can never fail. [A] | `test/matrix/handoff_status_matrix.dart:35` |
| B2 | `suggest_test.dart` and `debug_test.dart` never reach the success status write. [A] | `test/commands/suggest_test.dart:94-178` |
| B3 | `test/matrix/handoff_status_type.dart` is a hand-copied mirror of `HandoffStatus` with no sync test. [A] | |
| B4 | `MockClaudeRunner` matches by `message.contains(key)` and falls back silently to the first response; not driven by state or `PipelineEvent`. [A] | `test/pipeline/mock_claude_runner.dart:44-48` |
| B5 | Pipeline tests assert the context holds the tag the mock returned (cannot fail); bare-string slot keys. [A] | `test/pipeline/agent_pipeline_test.dart:58,285`; `pipeline_context.dart:42` |
| B6 | zedup: no test uses Stream/StreamController; Debug/Suggest/FlowCoordinator, `lib/commands/*`, `AgentFlowPoller` untested. [A] | |
| B7 | zedup emitter tests are 18/19 and 15/20 `contains()` on emitted source for emitters with no production callers. [A, callers V] | |
| B8 | dartrix: renderer, snapshot and config tests compare strings; snapshot status is a bare string where the shoelace app has a typed `TestStatus`. [A] | |

Good pattern to copy: zedup `agents_workflow_pane_handle_event_test.dart` feeds typed `PipelineEvent`s.

## C. Layering violations

- claudart: pipeline<->ui (executor prints and calls `arrowMenu`), pipeline<->flows, pipeline<->templates, `md_io.dart` importing pipeline and ui, session<->workspace, data/logging layers importing pipeline domain. [A]
- zedup: enums->ui (`state_hue.dart:18`), features->commands, chat screens->`lib/pipeline/surface`, several feature cycles. [A]
- dartrix: no wrong-direction imports; `src/shoelace/` mixes a typed model with two string-keyed ones. [A]

## D. Duplicates and drift

| # | Finding | Evidence |
|---|---|---|
| D1 | zedup `FaultClass`/`FaultSeverity` duplicate claudart's. zedup has 7 ErrorTypes/19 FailureTypes vs claudart 5/8; 8 standalone exceptions outside the taxonomy; `gitCheckoutFailed` misused. [A] | `zedup/lib/src/enums/` |
| D2 | zedup pins claudart at `9e70467`, 33 commits behind main; lacks errors, codegen, typed runner throws. [V count 33] | `zedup/pubspec.lock` |
| D3 | zedup `claudart_runner.dart` has its own runner hardcoding `--dangerously-skip-permissions`, an 8-minute timeout, no provider check, no typed throws; every error becomes `AgentResult.text`. [V flag at line 84] | `claudart_runner.dart:75-104,253-271` |
| D4 | zedup generators (`FlowChartEmitter`, `ViewerEmitter`, `ProjectionEmitter`) have no production callers; none has an artifact enum or staleness check. [V] | `zedup/lib/src/codegen/` |
| D5 | zedup `setup_post_walk` always regenerates and `dart compile exe`s to `~/bin/zedup`; package root falls back to cwd. [A] | `setup_post_walk.dart:47-58` |
| D6 | dartrix and consumers: git dep without `ref`; all lock at `14cbc3e`; local dartrix branch is one commit ahead. [A] | |
| D7 | Three snapshot models: dartrix `ShoelaceSnapshot`, shoelace `CoverageSnapshot`, zedup `TestPoint`/`UsagePoint`. [A] | |
| D8 | claudart `lib/errors` and `lib/codegen` are not exported from `claudart.dart`. [A] | |

## E. Docs vs code

- `design.md:62` false (A1). `design.md` §7 parse-once target unmet: `debug.dart:65-79` parses 5 times. [A]
- dartrix PLAN.md lists Phase 1 not started though `gap_cross_reference.dart` exists; README link to `ShoelaceLayout` stale; version labels disagree (pubspec 0.1.2 vs PARADIGMS 0.6.0). [A]
- dartrix PARADIGMS promises a posture function and lint rules; neither exists in dartrix (rules live in claudart). `DartrixConfig` is unused. [A]
- `suggest_template.dart:52` mentions status `suggest-needed`, which does not exist. [A]

## F. Dead / test-only code (beyond #79)

`readProjectEnv` [V], `githubLogSection()` and its unpassed parameter [A], `expectsSuggest`/`expectsDebug` [V], `test/matrix/pipeline_component.dart` [A], `add.dart` mermaid/changelog answers prompted and unused [A]. Open question: why the census (#79) missed these.

## G. Invisible flow decisions (logging targets)

claudart: no-route-tag silent skip (`pipeline_executor.dart:206-212`), strict abort emits `PipelineCompleted` (`:201`), approve/refine/exit have no typed event (`:257-286`), typed exception flattened to string in `AgentFailed.reason` (`:145`), silent sonnet fallback, status-gate override only `print`s, unknown status silent, `PlannerLog` only recorded in `flow.dart`. [A]
zedup: dispatcher catch-all, version guard drops `binaryVersion`, corrupt checkpoint deleted silently, swallowed save/write failures, silent project/package-root fallbacks. [A]

## H. Naming (proposals, not renames)

claudart: `updateStatus`->`withHandoffStatus(HandoffStatus)`, `readSection` vs `extractSection` (same regex, different defaults), `debug_mode.dart`->`trace_env.dart`, `choice == 1/2`->`ApprovalChoice`, `needsSuggest` vs `readyForSuggest` meaning unclear, `_cmd` suffix on two files.
zedup: `claudart_runner.dart` holds `AgentDispatcher`, `minClaudartVersion` is an exact match, field `mode` typed `AgentFlow`, duplicate `ClaudeRunner` typedef name.
dartrix: `Dartrix`->`CoverageMatrix`, `getSelector`->`selectorFor`, `aggregateStateFor` returns String.

## I. Open issues carried (liitx/claudart)

#87 routing/benchmark, #85 corrupt registry, #83 runner mutations, #82 text test, #81 command-dir contamination, #79 test-only census, #77 upstream hang, #76 ProofNotation coverage, #75 doctor mutations, #56 relink reverts hand-edits.

## Corrections to earlier assumptions

- The audit said 8 zedup lib files use AgentModel/AgentFlow; the coordinator count is 16. [V]

## Resolution log (branch refactor/typed-handoff-status, local commits, not pushed)

| Ledger | Status | Commit |
|---|---|---|
| A1 untyped writes / no transition function | fixed: `HandoffStatus.after(HandoffEvent)`, `applyHandoffEvent`; design.md corrected | 1f84bb8, 04ee7ad |
| A4 debug precondition defined twice | fixed: `canStartDebug`, and a test keeps it equal to `after(fixApplied)` | 02cc4a6, 58ed8d9 |
| A5 string compares in suggest/debug | fixed | e9fd1df |
| B2 success path of suggest/debug never tested | fixed: status matrix per persisted state, expected from `after` | e9fd1df, 225781e, 58ed8d9 |
| A2 `debug-in-progress` never written | open: `fixApplied` writes debug-complete directly; `debugStarted` has no caller yet | - |
| A3 flow prompt writes `ready-for-suggest` | fixed: every agent prompt names statuses through `HandoffStatus`; a scan test fails on any typed status | cc8069b |
| A6 dead getters `expectsSuggest`/`expectsDebug` | open: topology shows expectsDebug == canStartDebug | - |
| E `suggest-needed` mention | fixed; template-wide scan test added | 272fa19 |
| Behaviour change | `runDebug` no longer offers "Run debug anyway?"; a wrong status is a typed rejection before any model call. `runSuggest` rejects `debugComplete` | 225781e, 58ed8d9 |

| Transition logging | `transitions.jsonl` records every applied move (command, from, event, to); reset commands log spec-unlisted moves as `rejected: true` without throwing | 224caad, d270c5e |
| Topology doc | `docs/topology/handoff_status.md` generated by `make topology`; a test fails when it is stale | 517957b, 4b12a39, 783f253 |
| New events from real behaviour | `rotatedEmpty`, `reminderSaved` | 2d9f1a7 |
| OPEN design question | the blank handoff left by kill/teardown/empty-rotate reads `suggest-investigating`, but the log says the move lands in `noHandoff`; decide which notion the state machine means | - |
| Still no code caller | `saveUnconfirmed`, `saveConfirmedExploring`, `debugStarted`, `debugBlocked` (agent-performed via prompts) | - |
