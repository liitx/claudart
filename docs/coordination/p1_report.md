# Brief P1 report — research only, no code changed (2026-10-12)

Method: step 0 real runs with the debug flag on (`CLAUDART_DEBUG=1`, `--debug`), then five read-only Opus audits
(logging, initialization trace, handoff template + state, per-env codegen + dartrix matrix, zedup consumption).
Tags: [V] verified against code or a real run; [A] audit claim not re-checked by the coordinator.
Layer names follow `brief_decomposition.md` section 0 (tool + purpose). STOP: awaiting owner approval; no implementation.

## Headline findings

1. **The claudart-link per-env codegen is wired to nothing.** `lib/generated/dependency_config.g.dart` (`usesDartrix`)
   is imported by no file in lib/bin/test/tool. [V] Its doc comment promises gating; it gates nothing.
2. **zedup-setup codegen is broken for opt-in.** For any tool other than zedup it emits
   `import 'package:<tool>/manifest.dart'` (`zedup/lib/src/codegen/user_config_codegen.dart:120-122`); neither claudart
   nor dartrix has a `manifest.dart`, and `zedup/manifest/` holds only `zedup.yaml`. [V] `runSetupPostWalk` ignores
   setup answers and builds one binding. [A]
3. **The dartrix matrix is filled by hand, not from the per-env codegen.** zedup manifests declare `coverageAxes`; no
   code consumes them. [A] The handoff matrix ignores 6 of 8 statuses (only touched variants are checked). [A]
4. **The session state machine is documentation only.** No transition function; status writes are bare strings;
   `debug-in-progress` is never written; `/save` transitions in design.md are not implemented. [V]
5. **`--debug` covers only agent pipeline steps.** `claudart --debug status`, `doctor`, `setup`, `link` write no trace. [V]
   The trace writes system prompts and messages unmasked, in sensitivity-mode workspaces. [V by real probe]
6. **`claudart setup` never reads `workspace.json`, never checks freshness, never checks the lock.** A "ready session"
   is just a written `handoff.md`. [A, consistent with ledger]
7. **zedup bump to claudart main is safe.** In a /tmp copy, pinning claudart to `c454f10` gave 0 analyze errors and all
   2122 zedup tests passed. [A] The version guard cannot see the drift (both are `2.0.0`, exact-match check). [A]

## D1. Layer map (layer x repo x owned types x hands to next layer)

| Layer (tool + purpose) | claudart | zedup | dartrix | Hands to the next layer |
|---|---|---|---|---|
| claudart workspace.json tool-selection config | `WorkspaceConfig`, `Registry`, `config.json`; only `owner.strict` is read; `agents`/`stack` written, never read [A] | setup answers (ignored) [A] | `DartrixConfig` (no consumers) [A] | nothing consumed downstream: pubspec regex is what link actually uses |
| claudart-link / zedup-setup per-env codegen | `ClaudartArtifact` x4, `dependency_config.g.dart` (unused) | `kZedupConfig` (`user_config.g.dart`), 3 unwired emitters | none | `kZedupConfig` reaches zedup UI; claudart's reaches nothing |
| dartrix matrix | `test/matrix/*` hand-written mirrors | `test/matrix/zedup_matrix.dart` hand-listed | `Dartrix`, `testSelector` | cells declared by hand |
| claudart handoff template | `handoff_template.dart`, `HandoffStatus`, `AgentCategory` | parses handoff itself with its own section names | none | bug-shaped only |
| claudart handoff.md session state | `SessionState` (status typed, rest String) | reads/writes `handoff.md` directly, own status strings [A] | none | in-process stream only inside zedup |
| claudart pipeline agent run + logging | `PipelineExecutor`, `SessionLogger`, `PlannerLog`, trace | `AgentDispatcher` own runner (hardcodes `--dangerously-skip-permissions`, no trace) | none | three log sinks, no shared schema |

Wrong-direction imports: see `ledger.md` section C (pipeline<->ui, pipeline<->flows, zedup enums->ui, etc.).

## D2. Initialization trace (real sandbox run, HOME and workspace in /tmp/p1; real workspace unchanged [A: agent-verified diff])

`claudart setup`: `--debug` flag -> `detectGitContext()` (git process) -> `Registry.load` (re-read every call; corrupt JSON ->
empty, #85) -> exact-string `findByProjectRoot` (fails when the path is a symlink such as /tmp vs /private/tmp) ->
`SessionState.parse` of handoff.md -> menu if active -> skills placeholder check -> 4 prompts -> optional scan + token
abstraction (sensitivity) -> write `handoffTemplate(...)` -> one `interactions.jsonl` line. Never: workspace.json, `stateOf`,
lock, pubspec, debug flag. [A]
`claudart link`: root + name resolution -> sensitivity -> registry write -> loop over `ClaudartArtifact.values`
(commandTemplates, claudeMdTail, readmeRoadmap, dependencyConfig) -> seed `workspace.json` once (agents = all 10 AgentFlow,
knowledge []). link logs nothing. [A]
Tools used: `git`, `find`, `dart compile exe` (only with `--recompile`). Debug output captured: none exists for either
command (the only record is the interactions.jsonl line). [V for status/doctor, A for setup/link]

## D3. Handoff-template readiness by work type

| | bug | feature | refactor | research | audit |
|---|---|---|---|---|---|
| `AgentCategory` variant | yes | yes | yes | yes | **missing** |
| Handoff sections | fit | bug-shaped | bug-shaped | bug-shaped | none |
| Transitions | suggest/debug only | reuse | reuse | reuse (no implement phase) | none |
| `AgentFlow` | suggest, debug | none | none | `research` has no steps or command file | none |
| Tools/skills per state | none | none | none | none | none |
| Per-env codegen targets | none per type | none | none | none | none |
| Matrix cells | 2 of 8 statuses | none | none | none | none |

Sections: universal = Status, Expected Behavior, Scope, Constraints, Pending Issues; bug-only by name = Bug (really
Goal), Root Cause (feature needs Approach), Debug Progress (really Progress); optional = Suggest Resume Notes.
Written but never parsed by Dart: Constraints, "Specific question for suggest", "Classes / methods", Suggest Resume Notes.
`routeModel` (probe of all 90 cells): category has no effect; model depends only on intent x tier. [A, matches #87]

## D4. Drift report (which side is stale)

| Mismatch | Stale side |
|---|---|
| design.md:62 "delta is compiler-exhaustive" vs bare-string writes | **doc is wrong now; code should be fixed to match** |
| `flow_steps.dart:68` writes `ready-for-suggest` as initial status; design.md allows it only after another transition | code |
| `/save` two transitions (design.md:48,51) never written by `save.dart` | code (unimplemented) |
| `debug.dart` accepts only ready-for-debug; `sync_check` also debug-in-progress; debug never calls preflight | code (two definitions) |
| `suggest_template.dart:52` mentions nonexistent `suggest-needed` | template |
| `usesDartrix` doc promises gating | code (unimplemented) |
| zedup `capability.dart:151` "Dartrix iterates coverageAxes" | code (unimplemented) |
| zedup `zedup_tool.dart` points to `manifest/claudart.yaml`, `manifest/dartrix.yaml`, which do not exist | code |
| dartrix PLAN says Phase 1 not started; `gap_cross_reference.dart` exists; PARADIGMS posture function/lint rules not in dartrix | docs |
| `routeModel` comments mention fable (stale) | comments |

## D5. Overlap list and consolidation proposals

| Same concept modeled twice | Proposal |
|---|---|
| `HandoffStatus` vs `test/matrix/handoff_status_type.dart` hand mirror | derive from `.values`; name-compare test |
| `AgentFlow` (10) vs `PipelineFlowType` (5) | same |
| `ClaudartCommand` vs `ClaudartOperation` (`fromString` defaults unknown to `test`) | collapse into `ClaudartCommand`, remove the default |
| Debug precondition in `debug.dart` and `sync_check.dart` | one `HandoffStatus` getter |
| `AgentFlow.preferredModel` vs `routeModel` | single table (#87) |
| Status color switch x3 (`launch`, `status`, `setup`) | one getter on the enum |
| `readSection` vs `extractSection` | one function |
| `GeneratedFileWriter` x3 (claudart codegen, zedup user_config, zedup typed_projection) | one writer in dartrix |
| `FaultClass` etc. in claudart and zedup | zedup migration |
| "has dartrix" computed three ways (link, `stateOf`, add.dart) | one value owned by the tool-selection config |
| `sensitivityMode` in registry and workspace.json | one owner |
| Three snapshot models (dartrix, shoelace, zedup) | one |
| Which tools: workspace.json, pubspec regex, zedup answers | one owner (see Q1) |

## D6. String and flag inventory with typed replacements

| Family | lib / test | Typed replacement |
|---|---|---|
| Status literals | 17 / 29 | `updateStatus(HandoffStatus)`; wire map only in `HandoffStatus.value` |
| Section names | 31 / 10 | `enum HandoffSection { header }` + nested subsection enum; template renders from it |
| Slot keys | 0 direct / 27 | `PipelineContext` accepts only `PipelineSlot` |
| Command names | 36 / 51 | `ClaudartCommand` everywhere |
| Placeholder text `_Not...` | 35 / - | `Placeholder` enum or nullable fields |
| Debug env var read per call | - | read once into state |
| `confirm`/`choice == 1/2` ints | executor | `ApprovalChoice` enum |

## D7. Test redundancy (about 67 tests fold into 8 matrix groups) [A]

`failure_type_test` (8 + 8), `artifact_state_test` (17 = artifact x state), `session_state_test` (11 + 4 loop over
`HandoffStatus.values`), `agent_provider_test` (9), `pipeline_step_exception_test` (4 overlap), `xml_tags_test` (~6).
Plus test-honesty items B1-B8 in the ledger.

## D8. Logging audit

| Command / layer | Honors `--debug`? | Sink |
|---|---|---|
| Pipeline steps via `defaultClaudeRunner` (flow, suggest, debug, chat) | yes | `$CLAUDART_DEBUG_PATH`, default /tmp/claudart_debug.log |
| status, doctor, setup, link, save, scan, kill, ... | **no** [V status/doctor] | none |
| `SessionLogger` (scan, setup, doctor, central catch) | no, always on | `<workspace>/logs/*.jsonl`, performance.md |
| `PlannerLog` (flow only) | no, always on | `planner.jsonl` |
| zedup `AgentDispatcher` | bypasses trace | none; `EventEmitter` (events.jsonl) has no callers |

Flag state: CLI flag in a mutable top-level, env re-read per call; not in session state. zedup/dartrix cannot set it
(`debug_mode` not exported); zedup pipeline runs see the env var by accident. Failures: the central catch logs
`errorType.name` as a String; `scan.dart` and `doctor.dart` pass bare strings; trace `writeException` interpolates `$error`.
No log records expected-vs-actual; a malformed categorize result is silently dropped (`flow.dart:262`). Sensitivity: trace
writes prompt/message/stream unmasked (real probe output with fake secrets in /tmp/p1/logging_probe.log). [V]
Sample real output: the probe log shows the STEP / SYSTEM PROMPT / MESSAGE lines; `status` and `doctor` produced no trace.

Consolidation proposal (from the audit; owner approval needed): `DebugMode` in session state resolved once at CLI entry;
`LogKind` and `LogLevel` enhanced enums (kind owns sink, min level, sensitivity); sealed `LogEntry` (interaction, error
wrapping `ClaudartException`, planner decision, step, `ExpectationEntry(expected, actual, matched)`); one `Log.emit` that
gates, masks via the token map, and routes. "Expected" declared on the step/template (`AgentStep.expects`, the handoff
template's per-phase outcome), not in the logger, so the FSM stays the single source.

## Answers to the five open questions

1. **What is "the matrix"?** Today dartrix's schema is (variant x feature) with cells covered by `testSelector`. Proposal:
   keep that schema; variants = work types, features = handoff phase capabilities; the set of variants/features available
   comes from the per-env codegen, so cells for tools the user lacks do not exist. A second matrix (phase x tool) proves
   tool dispatch. Needs owner decision.
2. **What makes cached state stale?** Inputs: pubspec, `claudeTemplate`/`AgentFlow` code, roadmap.json, generic knowledge dir,
   registry path/symlinks, workspace.json. Only `claudart doctor` runs `stateOf` today. Proposal: run `stateOf` (plus
   workspace.json validation) at setup/launch.
3. **Typed schema for handoff metadata?** None. Proposal: `HandoffSection` enum + typed `SessionState` fields (work type,
   phase, dates, scope as `ScopeFile`s) + `version` on workspace.json.
4. **Layers of getters, and which enum owns each?** Proposal: `WorkType` owns sections/phases/skills/tools; `HandoffStatus`
   (renamed to phases) owns transitions, preconditions, color; the per-env codegen owns the enabled-tools registry;
   dartrix owns cells.
5. **Prior audit?** `ledger.md`; open = all of it except merged #84, #86. Corrections from P1: A3 was wrong as stated; new
   items: `/save` transitions unimplemented, `ClaudartOperation.fromString` default, four sections written never parsed,
   triplicated status color switch.

## Concerns raised by P1 (for owner decisions)

- zedup runner hardcodes `--dangerously-skip-permissions`; the harness flagged that string in audit output twice. It is a
  finding about zedup's code, not an instruction.
- Always-on debug is unsafe until the trace is masked (C5 confirmed).
- zedup version guard cannot detect pin drift; claudart exports nothing of `errors/`, `codegen/`, `debug_mode`.
- A const bool cannot gate imports; the workable design is a generated registry/barrel with only enabled tools' imports
  (limits: pubspec still resolves every dependency, tree-shaking already drops unused code, so gain is exposure not size).

## Decisions needed before Brief P2

1. Approve the logging consolidation shape (DebugMode in state, LogKind/LogLevel enums, sealed LogEntry, expected on the step).
2. Enum for the closed set (work types, phases) and sealed for data-carrying entries/events, reconciling dartrix's
   documented "enums, not sealed, for the matrix spine"?
3. Rename `HandoffStatus` variants to phase names (suggest/debug are commands, not phases)?
4. One owner for "which tools does this user have" (suggest: workspace.json, with pubspec detection feeding it).
5. Wire or delete: `usesDartrix` const, zedup's three unwired emitters, unused `DartrixConfig`.
6. Push `feat/mutation-runner-streams`?
