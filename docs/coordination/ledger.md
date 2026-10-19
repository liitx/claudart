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
| A6 `expectsSuggest`/`expectsDebug` | CORRECTED: not dead -- zedup's tests and tool/smoke.dart use them (only its lib/ does not). Kept as public API. `expectsDebug` now delegates to `canStartDebug` (same set); both pinned per variant against literal sets | this commit |
| E `suggest-needed` mention | fixed; template-wide scan test added | 272fa19 |
| Behaviour change | `runDebug` no longer offers "Run debug anyway?"; a wrong status is a typed rejection before any model call. `runSuggest` rejects `debugComplete` | 225781e, 58ed8d9 |

| Transition logging | `transitions.jsonl` records every applied move (command, from, event, to); reset commands log spec-unlisted moves as `rejected: true` without throwing | 224caad, d270c5e |
| Topology doc | `docs/topology/handoff_status.md` generated by `make topology`; a test fails when it is stale | 517957b, 4b12a39, 783f253 |
| New events from real behaviour | `rotatedEmpty`, `reminderSaved` | 2d9f1a7 |
| OPEN design question | the blank handoff left by kill/teardown/empty-rotate reads `suggest-investigating`, but the log says the move lands in `noHandoff`; decide which notion the state machine means | - |
| Still no code caller | `saveUnconfirmed`, `saveConfirmedExploring`, `debugStarted`, `debugBlocked` (agent-performed via prompts) | - |

## Resolution log, environments and surfaces (branch refactor/typed-handoff-status)

| Item | Status |
|---|---|
| Typed link state (`WorkspaceLinkState`, `linkStateOf`); two hand-repeated checks in launch/kill replaced | done |
| `ClaudartCommand.reachedFrom` / `supportsHeadless` / `handoffEvents` with drift tests against the sources | done |
| `docs/topology/environments.md` generated; design.md section 9 | done |
| Lifecycle matrix over 3 link states x dartrix on/off (6 environments): identical outcomes, no environment-dependent bug found | done |
| `make consumer-check` now also scans zedup for raw status writers; `updateStatus` deprecated | done |
| OPEN (zedup): read `effectiveStatus` in `parseClaudartHandoff`; replace 2 raw `updateStatus` writers with `applyHandoffEvent` | open |
| OPEN: dartrix has no behavioural effect; link/unlink not in the lifecycle matrix; agent surface not modelled | open |

## Resolution log, ownership across repos

| Item | Status |
|---|---|
| `make ownership` / tool/ownership/ownership_scan.dart: components per repo, duplicated names, tests asserting another repo's component behavior; docs/topology/ownership.md | done |
| claudart-owned `AgentModel` and `AgentFlow.preferredModel` had NO claudart tests (only zedup's): now pinned in agent_model_test / agent_flow_test | done |
| `AgentModel.sonnet.slug` was `claude-sonnet-5`; owner confirmed `claude-sonnet-5-5`. Fixed in claudart. zedup's test fixture `claudart_model_fixtures.dart` still hard-codes the old slug: update (or delete it, see the redundant-test item) when zedup bumps claudart | fixed here; zedup open |
| zedup: remove redundant assertions of claudart components (agent_result_test: HandoffStatus members; agent_dispatcher_test / claudart_model_test: AgentModel alias and bestFor*) | open (zedup branch) |
| zedup: delete its copy of the error taxonomy (ErrorType, FailureType, FaultClass, FaultSeverity), consume claudart's | open (Phase 1 step 8) |
| dartrix: shoelace fixtures hard-code zedup's BranchType names; use a fictional enum | open (dartrix branch) |
| workspace.json agents/knowledge/stack drive nothing in Dart; link's command files come from AgentFlow.values | open (design.md 9.5) |

## Resolution log, model metadata and the repository layer (PLAN.md Phase 14)

| Item | Status |
|---|---|
| Opus review: model metadata is per step; declared / resolved / observed; nothing reads the observed model today | recorded in PLAN.md Phase 14 |
| CORRECTION to commit 3299f5e: `AgentModel.slug` (and contextWindow, maxOutputTokens, fromSlug) have no reader anywhere, so the slug fix changed documentation, not runtime behavior | noted |
| `sensitivityMode` drift: registry.json false vs workspace.json true for claudart | open (Phase 14 step 3) |
| Repository layer: start with `HandoffStore` (load + apply) and move zedup's raw handoff writers onto it | open (Phase 14 step 1) |
| Capture a real `stream-json` run before adding an observed-model field | open (Phase 14 step 4) |

## Resolution log, source of truth and generation (PLAN.md Phase 15)

| Item | Status |
|---|---|
| Opus review with measured experiments; key numbers reproduced by the coordinator | recorded in PLAN.md Phase 15 |
| Decision: enums are the source of truth; no YAML mirror (ZedCommand 11 variants vs 6 in zedup.yaml, verified) | recorded |
| Decision: no per-environment facades / recompiles / build_runner / conditional imports for claudart | recorded; supersedes design.md 9.5's registry idea |
| First slice: enabled agents filter the generated command files (typed `WorkspaceSession.agents`, "empty = all") | open, awaiting owner's answer on what "user interfaces with" means |
| zedup: derive commands from ZedCommand, delete the YAML commands and the nonexistent `package:<tool>/manifest.dart` emission; do not commit `user_config.g.dart` | open (zedup branch) |
| Delete `DependencyConfigCodegen` / `dependency_config.g.dart` / `ClaudartArtifact.dependencyConfig` unless something reads it | open |
| Proof checks still missing: a drift test per zedup generated file; one shared `GeneratedFileWriter`; every generated symbol has a reader | open |

## Resolution log, workspace scoping

| Item | Status |
|---|---|
| Verified (two-workspace conformance): commands name only their own workspace; every lifecycle step leaves the other workspace and its registry entry byte-identical; an unregistered cwd changes nothing | done |
| Gap closed: baked-path flows mixed a baked workspace with cwd-resolved CLI calls; they now pass `--project <name>` | done |
| `claudart workspaces [--json]`, `WorkspaceSummary`, scope note in every command template | done |
| `--project <name>` selector (13 commands), `selectProject`, exported for zedup; real-binary tests incl. a destructive command | done |
| Found by the real binary: a project override skipped git detection (branch prompt, swallowed answer); `detectGitContext` takes a working directory, 8 sites fixed | done |
| Central error log now follows the selected project | done |
| Logs: `--project` writes targeted-by-project to the target workspace, `workspaces` writes listed N to the asking one (interactions.jsonl) | done |
| OPEN: re-run `claudart link` in existing workspaces to regenerate command files (doctor flags them stale) | open |
| OPEN (zedup): use `summarizeWorkspaces` / `selectProject` instead of parsing registry.json | open |
| OPEN: model-driven suggest/debug for another workspace are best run in that workspace's own session | by design |

## Resolution log, model metadata as observed state

| Item | Status |
|---|---|
| Owner decision: keep `slug`, `contextWindow`, `maxOutputTokens`; they are session context, each now has a reader | done |
| Real `stream-json` run captured: the result line's `modelUsage` names the model, window, output cap, provider, per-model tokens and cost; fixture `test/fixtures/claude_result_line_haiku.json` | done |
| Finding: observed haiku `maxOutputTokens` 32000 vs declared 8192 (drift is data; declared value not changed) | open: decide whether declared tracks the CLI's reported cap |
| `ModelObservation`, `reconcileModel`, `StepResult.models`, `AgentCompleted.intendedModel/models` | done |
| `logs/models.jsonl` via `logStepModels` (suggest, debug, flow, drift-tested by `ClaudartCommand.recordsStepModels`); `claudart status` shows the newest per step | done |
| Generated proof `docs/topology/model_metadata.md`; token conservation test (no extra call, no prompt change) | done |
| OPEN (zedup): read `models` from `AgentCompleted` in its own workflow pane instead of the intended model only | open |
| OPEN: only haiku was captured; sonnet/opus/fable observations and Bedrock id mapping not yet seen | open |
| Pre-existing mutation survivors, not from this work: `logger.dart` 20 (interactions/errors/performance code, lines 62-286), `status.dart` 27 (branch warning, next-step prints, `_truncate`); the new code in both is fully killed | open: file as an issue |

## Gap analysis across claudart, zedup, dartrix (2026-10-16)

Plans: plan_claudart.md, plan_zedup.md, plan_dartrix.md (same folder).

| Gap | Where | Evidence | Fix (plan step) |
|---|---|---|---|
| claudart branch not on main, so zedup cannot use the typed API | claudart | zedup pins claudart main (resolved 9e70467) | claudart 1 (merge) |
| zedup shows a blank handoff as a live session | zedup | consumer-check: 4 DISAGREE of 16 | zedup 2 |
| 2 raw status writers bypass the state machine | zedup | debug_coordinator.dart:191, suggest_coordinator.dart:187 | zedup 3 |
| zedup parses registry.json itself | zedup | PLAN Phase 14 | zedup 4 |
| zedup and dartrix CLAUDE.md carry no claudart workflow, knowledge base or PARADIGMS pointer; no hooks | zedup, dartrix | grep: 0 markers | zedup 6, dartrix 4, claudart 2 |
| No mechanism makes Claude Code route implementation through claudart | all | only claudart has a PostToolUse reminder | claudart 2 (generated settings artifact, posture consider/enforce) |
| dartrix v0.6.0 PARADIGMS unmerged; claudart reads v0.5.0 | dartrix | 5c23dfe on docs/four-roles-testing-paradigm | dartrix 1 |
| Stale generated command templates | claudart | doctor FAIL | fixed: `claudart link --no-sensitive`, doctor all OK |
| "Debug mode" for all workspaces | all | `--debug` / CLAUDART_DEBUG=1 trace | claudart 2 (env in the generated settings) |
| Coverage floor 74 vs measured 85.8 | claudart | check-coverage | claudart 3 |

## Resolution log, zedup consumes the typed handoff (2026-10-16)

| Item | Status |
|---|---|
| claudart PR #91 merged by the owner (ruleset `Protect main` has an admin bypass; no ruleset change was made) | done |
| zedup reader on effectiveStatus; both raw writers on applyHandoffEvent; consumer-check 16/16, 0 writers | done on zedup branch feat/consume-typed-handoff (local) |
| Redundant claudart-owned AgentModel test and fixture removed from zedup | done on that branch |
| `mutation_test` is claudart's wrapper of a third-party package; dartrix has no mutation API (folding it in is undecided); zedup borrows claudart's rules file | open: owner decision |
| Barrel exports ClaudartCommand, CommandEntry, SessionLogger so consumers need no path imports | done in this PR; zedup to switch to the barrel after merge |
| Ownership scan: ErrorType, FailureType, FaultClass, FaultSeverity declared in claudart and zedup | open: zedup step 5 |

## Resolution log, safe log writes (2026-10-18)

| Item | Status |
|---|---|
| Lost log lines: appends rewrote the whole file, so concurrent processes overwrote each other (4 processes x 100 lines kept 382 of 400) | fixed: `FileIO.append` under an exclusive file lock; the jsonl logs append one line |
| Torn writes: `RealFileIO.write` truncated before writing, a reader could see a cut-off line that the next rewrite kept | fixed: write to a staging file, rename over |
| Finding: Dart's plain `FileMode.append` is not safe across processes (370 of 400); the lock is per process, so isolates cannot test it, real child processes do | recorded in the tests |
| Cap is now soft: a log may run 50 lines past its cap before it is trimmed back (the rewrite happens once per 50 appends) | by design; tests pin both sides |
| Pre-existing mutation survivors in `logger.dart` (20: optional interaction fields, `logError`, `logPerformance`, `_writeJsonl` cap) and `file_io.dart` (`listFiles` extension filter, `linkExists`) | open: file as an issue |
| OPEN: `logError` and `logPerformance` still read-modify-write (they deduplicate or keep a table); now atomic on write, but two processes can still lose an update | open |
