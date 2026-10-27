# Methodical refactor

How a refactor is run when every step must be proven and nothing may be assumed.
This document is the feature's record: the stage sequence, the gap register, and
what each stage proved. It is written as the work happens, so it shows how the
work was actually done.

The approved plan is the source of the stage order (Phases 0 to 6). The
reasoning behind a stage is in `docs/session_log.md`; the roadmap entry is in
`PLAN.md`.

## Stage sequence

| Id | Name | Question it answers | Output | Proof type |
|---|---|---|---|---|
| PH0 | `toolLiveness` | Do the lints, tests, mutation and guards catch what they claim? | Tool-liveness matrix, call census | Seeded-defect table; counted reads |
| PH1 | `dependencyFamilies` | What depends on what? | Signature per symbol, family enum, `docs/topology/families.md` | Every symbol in exactly one family |
| PH2 | `useCaseMatrix` | What should happen in every state, per trigger? | Cells of status x event x trigger x link x sensitivity x dartrix | Expected derived independently, compared with the log |
| PH3 | `listenerDesign` | What reacts to a state change, and does it end? | Typed stream, per-cell switch | Closure graph has no cycle |
| PH4 | `closeGaps` | Which gaps are real, in what order? | One failing test, then one fix, per gap | Gates and mutation per item |
| PH5 | `crossPackageTruth` | Where do claudart, dartrix, zedup meet? | One portal document | Generated from code |
| PH6 | `verifyEndToEnd` | Does the whole still agree? | Re-run of stages 2 and conformance | Expected equals actual |

Parameters that scale it: the number of packages, the number of dependency
layers, and which proof types apply. A watcher reads the expected-versus-actual
record each stage writes.

## Gap register

Status: `open`, `closed` (with the proof), or `accepted` (with the reason).
Evidence is file:line as of the commit this was written against.

### State machine

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| S1 | `statusStreamMissing` | No status stream. The only stream is the pipeline's, with one subscriber | `logger.dart:203`; `pipeline_executor.dart:85` | open |
| S2 | `statusWrittenInManyPlaces` | Status written by direct string writes, not one writer | `debug.dart:67-70,182,335`; `save.dart:74`; `suggest.dart:125,294` | open |
| S3 | `rotateAndKillBypassWriter` | `rotate` and `kill` write the blank handoff outside `applyHandoffEvent` | `rotate.dart:181,200`; `kill.dart` | open |
| S4 | `agentsEditHandoffDirectly` | Agents edit `handoff.md` directly, bypassing the table | agent prompts, `docs/topology/handoff_status.md` | open |
| S5 | `perStatusSwitchesDuplicated` | Four per-status switches re-derive behavior | `launch.dart:238`; `status.dart:118`; `render.dart:38`; `save.dart:190` | open |
| S6 | `permissiveMoveLogging` | Setup, rotate, teardown, kill log a missing move as rejected and continue | `logger.dart:143` | open |
| S7 | `teardownPipelineUnlogged` | Teardown pipeline has no log subscriber; subscriptions are dropped | `teardown.dart:144`; suggest/debug/flow | open |
| S8 | `pipelineStateMachineUndeclared` | Pipeline FSM exists only as a comment | `pipeline_event.dart:3-24` | open |
| S9 | `performanceLogHasNoWriter` | `LogFile.performance` has no writer | `logger.dart:326` | open |

### Exits that leave no record

`save.dart:62,73`; `teardown.dart:75,138`; `kill.dart:103,114,126`;
`suggest.dart:101,231`; `setup.dart:100,104,164`; `rotate.dart:96,104,132`;
`launch.dart:49,80,137`; `logger.dart:229`. A save from a status with no save
move writes a checkpoint with no transition and no log. Status: open (E1, `exitsLeaveNoRecord`).

### Defaults and silent fallbacks

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| D1 | `defaultArmInLaunch` | `default:` arm | `launch.dart:158` | open |
| D2 | `wildcardArms` | Wildcard arms | `session_state.dart:29`; `failure_type.dart:82`; `claudart_command.dart:168,270`; `sync_check.dart:16,139`; `workspace_config.dart:41,61`; `chat_shell.dart:50`; `config.dart:80` | open |
| D3 | `corruptRegistryReadsEmpty` | Corrupt registry reads as empty | `registry.dart:103` | open |
| D4 | `unreadableWorkspaceConfigDisablesStrictMode` | Unreadable `workspace.json` makes `owner.strict` false | `suggest.dart:59`; `debug.dart:111`; `flow.dart:67`; `hook.dart:157` | open |
| D5 | `missingFileReadsEmpty` | Missing file reads as an empty string | `file_io.dart:41` | open |
| D6 | `homeDirectoryAssumed` | `HOME` assumed set | `paths.dart:75,79` | open |
| D7 | `tokenMapNotPersisted` | Token map updated but not persisted in setup and save | `setup.dart:191`; `save.dart:136` | open |
| D8 | `swallowedErrors` | Swallowed errors | `token_map.dart:91`; `link.dart:690`; `session_ops.dart:161` | open |
| D9 | `suggestAppliesReadyWithoutConvergence` | `suggest` writes the model's `ROOT_CAUSE` with `tagOr`, which returns `_Not determined._` when the tag is missing, and then applies `saveConfirmedReady` anyway: the status says the root cause is locked while the handoff says it is not determined | `suggest.dart:271,291-296`, `xml_tags.dart:30` | open |
| D10 | `placeholderSpelledThreeWays` | The "no root cause" placeholder is `_Not yet determined._` in the template, `_Not determined._` from `tagOr`, and `debug` compares only the first exactly (`debug.dart:219`), so the fallback reaches the debug prompt as if it were a real root cause. `save` and `teardown` use `startsWith('_Not')` and catch both | `handoff_template.dart:48`, `xml_tags.dart:30`, `debug.dart:219` | open |

### Binding and source of truth

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| B1 | `gitResolvedRepeatedly` | Git and registry re-resolved per command, 2 to 3 times with `--project` or debug | `bin/claudart.dart:155,175`; `failure_boundary.dart:49` | open, measure first |
| B2 | `registryParsedTwice` | Registry re-parsed inside `save` | `registry.dart:128` | open, measure first |
| B3 | `twoConfigParsers` | Two parsers for `config.json` | `config.dart:105`; `rotate.dart:212` | open |
| B4 | `duplicatedProjectFacts` | Project name and sensitivity held in more than one file with no agreement check | `registry.dart`; `workspace_config.dart` | open |
| B5 | `unlinkLeavesRegistryEntry` | `unlink` leaves registry entry, generated files, `.gitignore` lines, hooks path | `unlink.dart:27-41` | open, decide from data |
| B6 | `commandsIgnoreProjectOption` | `scan`, `report`, `map`, `doctor` ignore `--project` | `claudart_command.dart:179-208` | open |
| B7 | `knowledgeDirectoryAssumed` | Knowledge dir assumed under the workspaces root | `link.dart:247`; templates | open |

### Cross-package

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| X1 | `matrixCellNaming` | The type is `MatrixCell`; earlier notes named a type that does not exist | dartrix `matrix.dart:25` | closed (naming corrected here) |
| X2 | `dartrixCoverageIsRuntime` | dartrix `cover` and `gaps` are runtime, not compile-time | dartrix `matrix.dart:62-79` | open |
| X3 | `paradigmsPromiseMissingParts` | PARADIGMS promises a posture function and a lint package that do not exist | dartrix `PARADIGMS.md:20-42,184` | open (dartrix finding) |
| X4 | `handKeptMatrixMirror` | `HandoffStatusType` is a hand-kept mirror; `PipelineComponent` unused as an axis | `test/matrix/` | open |
| X5 | `noShoelaceSnapshotProducer` | claudart has no shoelace snapshot producer | zedup `launcher.dart:50` | open |
| X6 | `planFilesContradict` | Contradictions between the three PLAN files; claudart PLAN Phase 16 evidence stale | see stage 5 | open |
| X8 | `zedupDoesNotCompile` | zedup does not compile against this checkout: `claudart_runner.dart:246` reads `AgentFlow.preferredModel`, removed by the flow-link commit. `make consumer-check` therefore fails at compile time, before it reaches the status comparison. zedup's pinned claudart is older, so zedup itself is unaffected until it bumps. zedup is paused: recorded, not fixed | `make consumer-check` output | open |
| X9 | `consumerCheckHelpersMissing` | `consumer-check` copied only two helper files and had been broken since the scenarios began importing `ProjectFixture` and the unscripted helpers; it now copies them | `tool/consumer_check/run.sh` | closed |

### Tools that cannot see (found by stage 0.2)

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| U1 | `wildcardArmUndetected` | A wildcard arm in an enum switch is caught by no tool, so D2 can return unnoticed | stage 0.2 seed L6 (finding U1) | open |
| U2 | `bareStringComparisonUndetected` | A bare string compared with `==` is caught by no tool; `bare_string_for_enum` sees only switch dispatch | stage 0.2 seed L7 | open |
| U3 | `duplicateLiteralCheckAdvisory` | The duplicate-literal check is advisory: it prints and exits 0 | stage 0.2 seed W1 | open |
| U4 | `newLogFileNameUndetected` | A new log file name written as a literal is not caught, because the ownership guard knows only the names `LogFile` already holds | stage 0.2 seed T6 | open |

### Measured by the call census (stage 0.3)

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| N2 | `killReadsRegistryTwice` | Confirmed: `kill` reads the registry twice (load, then the re-read inside `save`) | `docs/topology/call_census.md`, kill rows | open |
| P1 | `logAppendReadsWholeLog` | Every log append also reads the whole log to count lines for trimming: 10 appends in `suggest` cost 10 reads, up to 2000 lines each for `steps.jsonl` | census, `suggest` row; `logger.dart:400` | open |
| C1 | `censusCoversLifecycleOnly` | The census covers only the lifecycle scenarios (setup, suggest, debug, teardown, kill, rotate); save, status, resume, link, hook and the other commands are not measured yet | census scope | open |
| N1 | `gitSpawnedTwicePerCommand` | Confirmed with real processes: every command spawns `git rev-parse --show-toplevel --abbrev-ref HEAD` twice where once is enough (`status`, `save`, `resume`, `preflight`, `scan`); `doctor` spawns five (three `rev-parse`, `config user.name`, `config user.email`); `status --project` spawns one. The second spawn's call site is not yet attributed | sandbox run, below | open |
| C2 | `censusSeesFileSeamOnly` | The census sees the FileIO seam only; git and `claude` process spawns need a separate measurement | census scope | open |

### Measured by the families (stage 1)

| Id | Name | Finding | Evidence | Status |
|---|---|---|---|---|
| F1 | `sevenStateWriters` | Exactly seven files drive handoff state, all processBound: `setup`, `suggest`, `debug`, `save`, `kill`, `rotate`, `teardown`. Each emits events itself; no single writer. This is the family the Phase 3 listener replaces. | `docs/topology/families.md`, `drivesState x processBound` | open |
| F2 | `stateReadersRederiveBehavior` | Four files observe state while processBound (`launch`, `status`, `workspaces`, `knowledge_templates`) and three are workspaceBound (`hook`, `session_ops`, `sync_check`): the readers that re-derive behavior per status | families doc | open |
| F3 | `commandsWithoutStateRecord` | 24 files reach processes or the terminal and never touch state, among them `flow`, `resume`, `doctor`, `link`, `unlink`: commands that change the session's world with no state record | families doc, `untouched x processBound` | open, review per command |
| F4 | `classifierMatchesDeclarations` | The classifier matches a name where it is only declared, so a portal's owner (`paths`, `registry`, `config`) sits beside its users | `topology_family.dart` header | accepted: owners are named in the doc |

### Measured by the transition matrix (stage 2)

| Id | Name | Finding | Evidence | Status |
|---|---|---|---|---|
| M1 | `legalMovesUndriven` | 24 of the table's legal moves were driven by no lifecycle scenario. Eight scenarios were added (unconfirmed and confirmed save, blocked debug and re-suggest, kill after debug, kill after a blocked debug, rotate with and without a pending issue from a fresh setup, suggest twice), leaving 14: all six `reminderSaved` cells (teardown's reminder path), five from `debugInProgress` (a state only a run killed mid-debug rests in), `saveConfirmedReady` from `readyForSuggest` and `needsSuggest`, and `readyForDebug --fixApplied`. Other command tests may cover some; none of them checks the logged move against the consumer view. A ratchet fails if the number grows | `docs/topology/transition_matrix.md` | open |
| M2 | `rejectedMovesUntried` | The lifecycle scenarios never make a command try a move the table rejects, so the "setup over a live handoff" rejection is covered only by its own separate test | transition matrix, rejected section | open |
| M3 | `environmentsDoNotChangeStateMachine` | Proven: the logged moves of every scenario are identical in all six link-state x dartrix environments, so those two axes do not change the state machine | `transition_matrix_test.dart`, "identical in every environment" | closed |


### Measured in real logs

Source: the real workspace logs of this machine (`transitions.jsonl` 44 moves
from 2026-10-19 03:54 to 2026-10-20 12:56, `errors.jsonl` 8 fingerprints,
`interactions.jsonl` 54 rows, `models.jsonl` 107 rows), read-only, counts only.

| Id | Name | Finding | Evidence | Status |
|---|---|---|---|---|
| R1 | `interactionLogCoversFourCommands` | Only `setup`, `doctor`, `scan` and `workspaces` write to the interactions log; every other command leaves no interaction record, so real command usage is invisible | `interactions.jsonl`: 54 rows, 4 commands | open |
| R2 | `suggestFromDebugCompleteRejectedInRealUse` | Real use tried `suggest` from `debug-complete` twice and it was rejected with `invalidHandoffTransition`; no lifecycle scenario tries it | `errors.jsonl`, fingerprint `suggest.invalidHandoffTransition` | open |
| R3 | `realUseNeverTearsDown` | 8 sessions ended with `kill` from `debugComplete`, none with `teardown`, so the skills-update path did not run in real use over these two days | `transitions.jsonl` | open |
| R4 | `realUseHitsNineOfThirtyThreeLegalCells` | Real moves touched 9 of the table's 33 legal cells; every one was legal and none was rejected | `transitions.jsonl` | open |
| R5 | `stepLogAbsentInRealUse` | No workspace has a `steps.jsonl`: the installed binary predates step logging, which is in unpushed local commits | workspace log directories | open, collect after a rebuild |
| R6 | `errorLogIsMostlyEnvironmentChecks` | 7 of the 8 error fingerprints come from `doctor` environment checks; one comes from a state move | `errors.jsonl` | open |
| R7 | `logSchemaUnversioned` | Of 107 model rows only 40 carry a role and 16 an accounting field: older rows lack fields and nothing marks which schema a row follows | `models.jsonl` | open |
| R8 | `fixAppliedFromReadyForDebugIsDebugPrecondition` | `readyForDebug --fixApplied` is never produced as a move by current `debug` (it writes `debugStarted` first; real logs show it produced up to 2026-10-20 08:07), but `debug` uses the cell as its start check before any model call (`debug.dart:139`) and `canStartDebug` is tested to agree with it. Measured in a scratch copy: making the cell illegal makes all 24 lifecycle runs that call `debug` fail (4 scenarios x 6 environments). The earlier "dead cell" claim was wrong: it is unused as a move and load-bearing as a check | scratch experiment, `debug.dart:139`, `transitions.jsonl` | open (decide: keep as the precondition, or check `debugStarted` instead and then remove) |
| R9 | `killAllowedFromEveryLiveStatus` | The table allows `killed` from all six live statuses, including `debugComplete`. The owner's rule is that `kill` is only for a handoff that is not confirmed and `teardown` is for a root cause and fix that are completely done (teardown itself asks "confirmed resolved?": yes archives and updates `skills.md`, no saves a reminder). The table does not enforce that rule | `session_state.dart` `killed` arm, `teardown.dart:96-110`, `kill.dart` doc | open |
| R10 | `statusDisagreesWithHandoffContent` | Of 179 archived handoffs and checkpoints, 17 say `suggest-investigating` while holding a real root cause and scope, and 1 says `ready-for-debug` with a placeholder root cause: about 10% have a status that does not follow the knowledge transfer in the handoff | the real workspace `archive/` | open |
| K1 | `workspaceKnowsNoFeatures` | The workspace records no Feature variants: `workspace.json` holds owner, project and session only, and `skills.md` is keyed by branch, category and files, not by Feature variant. Owner's direction: when a Feature variant is updated, the workspace should know which features exist in it. Scope not yet confirmed (derived from the project's enums, or declared) | `workspace.json`, `skills.md` | open, awaiting the owner's scope |
| K2 | `handoffHasNoType` | One `handoffTemplate` function renders every handoff (`setup.dart:179`, `rotate.dart:191`); the handoff records no type. `flow` classifies an `AgentCategory` in its own run and logs it, but never writes it into the handoff | `handoff_template.dart:3`, `flow.dart:226` | open |
| K3 | `scopeIsOneShapeForEveryKindOfWork` | `suggest` writes the same Scope sub-sections (files, entry points, classes, must-not-touch) for a bug, a feature, a refactor and a spike | `suggest.dart:277-284` | open |
| K4 | `knowledgeNotKeyedByFeature` | Knowledge is generic files plus one file per project; no file is keyed by a Feature variant, and `suggest` is told to read every generic file listed for the workspace, not the ones relevant to the handoff's feature | `knowledge/` layout, `setup_template.dart:31-39` | open |
| K5 | `threeCategoryTaxonomies` | `AgentCategory` (feature, bug, refactor, research, setup, gui), `TeardownCategory` (the skills categories) and the owner's handoff types (bug, feat, refactor, spike, story) are separate lists with no mapping between them | `categorization.dart:148`, `teardown.dart:195-209` | open |

## Gap to family

Each gap is placed in a family from `docs/topology/families.md` (state role x
reach layer) or marked as needing a new variant. A gap is placed in a family
only when the code it concerns is in `lib/` or `bin/`, where the scan reads;
a gap about a repo other than this one, or about tools and tests, has no
family today and names the variant it needs. The test
`test/topology/gap_register_test.dart` fails if a gap is missing from this
table, a family name is not a real `StateRole x ReachLayer` pair, or a "new"
variant is not in the proposals below.

| Id | Family | Verdict |
|---|---|---|
| S1 | drivesState x pure | existing |
| S2 | drivesState x processBound | existing |
| S3 | drivesState x processBound | existing |
| S4 | — | new: TriggerSource |
| S5 | observesState x processBound; drivesState x processBound; observesState x pure | existing |
| S6 | observesState x fileSeam | existing |
| S7 | drivesState x processBound | existing |
| S8 | — | new: StateMachineKind |
| S9 | observesState x fileSeam | existing |
| D1 | observesState x processBound | existing |
| D2 | untouched x pure; drivesState x pure; drivesState x workspaceBound; observesState x workspaceBound; untouched x workspaceBound; untouched x processBound | existing |
| D3 | untouched x workspaceBound | existing |
| D4 | untouched x workspaceBound; drivesState x processBound | existing |
| D5 | untouched x fileSeam | existing |
| D6 | untouched x workspaceBound | existing |
| D7 | drivesState x processBound | existing |
| D8 | untouched x fileSeam; untouched x processBound; observesState x workspaceBound | existing |
| D9 | drivesState x processBound | existing |
| D10 | drivesState x processBound; untouched x pure | existing |
| B1 | untouched x processBound | existing |
| B2 | untouched x workspaceBound | existing |
| B3 | untouched x workspaceBound; drivesState x processBound | existing |
| B4 | untouched x workspaceBound | existing |
| B5 | untouched x processBound | existing |
| B6 | drivesState x pure; untouched x processBound | existing |
| B7 | untouched x processBound | existing |
| X1 | — | new: OwningPackage |
| X2 | — | new: OwningPackage |
| X3 | — | new: OwningPackage |
| X4 | — | new: CodeTree |
| X5 | — | new: OwningPackage |
| X6 | — | new: OwningPackage |
| X8 | — | new: OwningPackage |
| X9 | — | new: CodeTree |
| U1 | — | new: CodeTree |
| U2 | — | new: CodeTree |
| U3 | — | new: CodeTree |
| U4 | — | new: CodeTree |
| N1 | untouched x processBound | existing |
| N2 | untouched x workspaceBound | existing |
| P1 | observesState x fileSeam | existing |
| C1 | — | new: CodeTree |
| C2 | — | new: CodeTree |
| F1 | drivesState x processBound | existing |
| F2 | observesState x processBound; observesState x workspaceBound | existing |
| F3 | untouched x processBound | existing |
| F4 | — | new: CodeTree |
| M1 | — | new: CodeTree |
| M2 | — | new: CodeTree |
| M3 | — | new: CodeTree |
| R1 | observesState x fileSeam; untouched x processBound | existing |
| R2 | drivesState x processBound | existing |
| R3 | drivesState x processBound | existing |
| R4 | drivesState x processBound | existing |
| R5 | observesState x fileSeam | existing |
| R6 | untouched x processBound | existing |
| R7 | observesState x fileSeam | existing |
| R8 | drivesState x processBound; drivesState x workspaceBound | existing |
| R9 | drivesState x processBound; drivesState x workspaceBound | existing |
| R10 | drivesState x processBound; observesState x workspaceBound | existing |
| K1 | untouched x workspaceBound; drivesState x processBound | existing |
| K2 | drivesState x processBound; untouched x pure | existing |
| K3 | drivesState x processBound | existing |
| K4 | untouched x workspaceBound; untouched x pure | existing |
| K5 | untouched x pure; drivesState x processBound | existing |

### Proposed new variants

| Name | Axis | Evidence | Needed by |
|---|---|---|---|
| `StateRole.reactsToState` | state role | No code subscribes to a status transition today; the stage 3 listeners are exactly such files, so they have no family | stage 3 (no gap yet) |
| `TriggerSource` | new axis: command, agentEdit, pipelineEvent, externalReader | Agents write statuses by editing `handoff.md` per their prompts (`handoff_status.md`, prompt references); no file family describes a trigger that is not code in this repo | S4 |
| `StateMachineKind` | new axis: handoff, pipeline | `StateRole` is about the handoff only; `PipelineEvent` is a second state machine whose files read as `untouched` | S8 |
| `OwningPackage` | new axis: claudart, dartrix, zedup | The scan reads one repo; dartrix and zedup gaps cannot be placed | X1, X2, X3, X5, X6, X8 |
| `CodeTree` | new axis: library, binary, tool, test | 178 files under `tool/` and `test/` are not scanned; lints, guards, scenarios and the census live there | X4, X9, U1-U4, C1, C2, F4, M1-M3 |
| `ReachLayer.siblingBound` | reach layer | 11 files in `lib/` name zedup or dartrix in code (`dependency_config`, `plan_template`, `doctor`, `link`, ...) and are spread across the other layers | none yet |

## Proposed order (draft, to be reviewed with claudart and the owner)

Derived from the register, the family table and the real logs; nothing here is
started. Each step lists what it needs first and the test that must fail
before the change and pass after.

| Id | Name | Gaps | Needs first | Pass condition (written before the change) |
|---|---|---|---|---|
| Q1 | `guardsThatSee` | U1, U2, U3, U4 | nothing | `make liveness` reports CAUGHT for a wildcard arm on an enum switch, a bare string compared with `==`, a duplicate literal (as a gate, not advice) and a new log-file-name literal; existing violations are held by a ratchet so later steps cannot add more |
| Q2 | `intendedBehaviorDecided` | M1, M2, R2, R3 | Q1 | the owner decides, per cell, whether each undriven or rejected-in-real-use move is wanted (first: `suggest` from `debugComplete`, `kill` versus `teardown`); each decision becomes a lifecycle scenario that fails before the code agrees; the undriven-cell ratchet reaches 0 or each remaining cell is marked unreachable with the reason |
| Q3 | `oneWriterForStatus` | S2, S3, E1 | Q2 | a guard fails if `handoff.md` status is written anywhere but `applyHandoffEvent`; the seven state-driving command files go through it; every early exit writes a record (the census shows no unrecorded exit) |
| Q4 | `asynchronousTransitionStream` | S1, S6, S7, S8 | Q3 | the totality, safety, termination, order, drain and isolation proofs of stage 3, each as a test; the logger is a subscriber and the `onTransition` callbacks are gone; `teardown` and the pipeline publish too |
| Q5 | `logsCoverEveryCommand` | R1, R5, R7, S9 | Q4 | every command leaves an interaction record (a matrix over `ClaudartCommand`); a real run after a rebuild produces `steps.jsonl`; each log row names its schema version; `performance` has a writer or is removed |
| Q6 | `noSilentFallbacks` | D1 to D8 | Q1 | a corrupt registry, an unreadable `workspace.json` under strict mode, a missing `HOME`, an unpersisted token map and each wildcard arm become a typed failure or an explicit variant, each with the failing test first |
| Q7 | `measuredRedundancyRemoved` | B1 to B4, N1, N2, P1 | Q5 | `make spawn-census` and the call census show git spawned once per command, the registry parsed once, the log append not reading the log; the before and after counts are recorded here |
| Q8 | `familiesGrowWhereDataSaysSo` | S4, S8 and the proposed variants | Q4 | each proposed variant is added only with a file that needs it: `reactsToState` with the first listener, `TriggerSource` with agent-edit detection, `CodeTree` when tools and tests are scanned; the families doc and its drift test change with them |
| Q9 | `crossPackageTruth` | X1 to X9 | Q8 | one generated portal document across claudart, dartrix and zedup; the zedup compile break (X8) and the three contradicting plans are listed for their owners; no edit to dartrix or zedup from here |

Why this order: Q1 first because every later step needs a tool that would
notice a regression. Q2 before any code because the real logs show behavior
the table does not describe (R2, R3), and only the owner can say which is
intended. Q3 before Q4 because a stream of transitions is only complete if one
writer publishes them. Q6 depends only on Q1 and can run beside Q3 to Q5.

## Stage records

Each entry states the pass condition first, then the observed result.

### Stage 0.2 - tool liveness

Pass condition: for every tool and every defect shape it claims to catch, a
seeded defect in a scratch copy of the repo is reported. A defect it does not
report is a finding. The working tree is never seeded; the harness is
`tool/refactor_audit/liveness.sh` (`make liveness`) and copies the repo first.

Observed (18 seeds): 15 caught, 3 missed. The 18th seed (T7) is the call
census doc drifting, added when the script moved into `tool/`.

| Id | Name | Tool | Defect | Result |
|---|---|---|---|---|
| A1 | `typeError` | analyzer | type error | caught |
| A2 | `unusedImport` | analyzer | unused import | caught |
| L1 | `stringSwitchWithActions` | custom_lint `bare_string_for_enum` | string switch with actions | caught |
| L2 | `enumValuesLoopInOneTest` | custom_lint `enum_values_loop_in_single_test` | enum `values` loop in one test | caught |
| L3 | `identicalSwitchArms` | custom_lint `ungrouped_identical_switch_cases` | identical arms | caught |
| L4 | `confirmWithoutPromptFunction` | custom_lint `unconditional_confirm_requires_prompt_fn` | `confirmFn` true, no `promptFn` | caught |
| L5 | `enumSwitchMissingVariant` | analyzer `missing_enum_constant_in_switch` | enum switch missing a variant | caught |
| L6 | `wildcardArmOnEnumSwitch` | any | wildcard arm on an enum switch | **missed** |
| L7 | `bareStringComparison` | any | bare string compared with `==` | **missed** |
| W1 | `sameFileDuplicateLiteral` | `check_duplicate_literals` | same-file duplicate literal | caught (advisory, exit 0) |
| T1 | `logFileNameLiteralInLib` | literal ownership guard | log file name literal in `lib/` | caught |
| T2 | `testTitleNamingTypeAsText` | literal ownership guard | test title naming a type as text | caught |
| T3 | `handoffDocDrift` | handoff topology test | generated doc drift | caught |
| T4 | `modelIdLiteralInLib` | model metadata guard | model id literal in `lib/` | caught |
| T5 | `environmentDocDrift` | environment topology test | generated doc drift | caught |
| T7 | `callCensusDocDrift` | call census test | generated doc drift | caught |
| T6 | `logNameLiteralNotInLogFile` | literal ownership guard | log name literal not yet in `LogFile` | **missed** |
| R1 | `orderDependentTest` | random-order suite | order-dependent test (passes in declared order) | caught |

Not seeded here: mutation testing. It was observed alive in the earlier
mutation runs, which reported survivors per file, and `edit_files.dart` cannot
be measured by the batch tool because of upstream issue #77.

### Stage 0.3 - observation seam

Pass condition: a test-only wrapper counts every call a command makes through
the FileIO seam without changing what it does, and the counts are generated
into a doc that fails when the code disagrees.

Observed: `test/helpers/counting_file_io.dart` (`CountingFileIO`),
`test/helpers/call_census.dart` (`CensusFile`, the complement kind `other`),
and `test/topology/call_census_test.dart`, which writes
`docs/topology/call_census.md` under `make topology`. The first run confirmed
N2 and found P1. Both are recorded above, not yet fixed.

Process spawns, measured with the real compiled CLI in a throwaway git
project (`tool/refactor_audit/spawn_census.sh`, `make spawn-census`, a `git` shim on `PATH` that logs each call and
delegates), `CLAUDART_WORKSPACE` pointed at a temp directory, project linked
with `claudart link --no-sensitive`. Wrapper noise (`dart run` itself calls
git) is excluded by running the compiled binary.

| Command (linked project) | git spawns |
|---|---|
| status | 2 |
| status --project proj | 1 |
| save | 2 |
| resume | 2 |
| preflight suggest | 2 |
| scan | 2 |
| doctor | 5 |
| hook pre-edit | 1 |

Not yet measured: `claude` spawns (needs the model call path), `link` itself
beyond one spawn before its prompts, and the second spawn's call site.

### Stage 1 - families

Pass condition: every file of `lib/` and `bin/` is in exactly one family, the
family is read from what the code does and not from its name or folder, and a
file matching no portal is the complement, not an unclassified bucket.

Observed: `test/helpers/topology_family.dart` (`StateRole` x `ReachLayer`,
`topologyFamilyOf`, `groupByFamily`) and `test/topology/families_topology_test.dart`,
which writes `docs/topology/families.md` under `make topology`. 139 files
classified; one test per variant proves each role and layer is found in its own
code shape, comments are ignored, and the grouping puts every file in exactly
one family. The first scan counted names in comments and declarations, which
moved type files such as `failure_type.dart` into the workspace layer; the
patterns were made call-shaped and the comment lines dropped, and the count is
now as in the doc.

Not done here: the import direction check (does a lower layer import a higher
one) is deferred. It needs resolved usage, not text, to avoid flagging a file
that imports only a type.

### Stage 2 - use-case matrix (first cut)

Pass condition: every one of the 104 (status, event) cells is classified as
legal-and-driven, legal-and-undriven, rejected-and-tried, or
rejected-and-untried, from the moves real commands logged, and the number of
undriven legal cells cannot grow.

Observed: `test/topology/transition_matrix_test.dart` writes
`docs/topology/transition_matrix.md`. The legality of a cell comes from
`HandoffStatus.after`; its independent expectation is the literal table in
`test/session/handoff_transition_test.dart`, which this matrix does not
duplicate. 24 legal cells are undriven (M1). The trigger-source axis (command,
agent edit, pipeline event, external reader) is not yet in the matrix: only
commands trigger moves today, and agent edits are not observable until the
working-tree check exists (S4).

### Stage 3 - listener design (for review, no code yet)

Computed from `HandoffStatus.after` (all 104 cells), not assumed:

- Seven statuses form one strongly connected component: every status except
  `unknown` reaches every other. `unknown` has no outgoing move and no move
  reaches it. Self-loops: `suggestInvestigating`, `readyForDebug`,
  `debugInProgress`.
- So no argument over statuses can prove a listener chain ends: sessions
  repeat by design. Termination has to be proven over events, per chain.

Proposed shape (one writer, one stream, listeners chosen by an exhaustive switch):

1. `applyHandoffEvent` stays the only place a status changes (closes S2, S3);
   it publishes each `HandoffTransition` on an asynchronous broadcast
   `Stream<HandoffTransition>` (owner decision: async). The file write and the
   publish happen in the writer; listeners run after, in later turns of the
   event loop, in the order the transitions were published.
2. A `HandoffListenerKind` enum names every reaction; a `listenersFor` switch
   over the transition's (status, event) cell returns the kinds that run, with
   no default arm, so a new event or status fails to compile until it is
   decided. The first kind is the logger (replaces the `onTransition`
   callbacks, closes S7's logging half).
3. A listener that must start the next sequence returns the next
   `HandoffEvent`, never applies it itself; the writer applies it, so every
   hop is a transition on the same stream and in the same log.

Proof obligations, each a test written before the code:

| Obligation | Check |
|---|---|
| Totality | `listenersFor` is an exhaustive switch over every cell, no wildcard |
| Safety | for every cell and every next event a listener can return, the event is legal from the status the cell lands in (checked over all 104 cells) |
| Termination | the relation event -> events a listener may return is acyclic (checked by topological sort over the 13 events); a chain is therefore at most 13 hops |
| Record | each hop is one line in `transitions.jsonl`, and the matrix test reads them |
| Order | listeners see transitions in publication order, and a listener-emitted event is queued behind the ones already published (checked with a recorded sequence) |
| Drain | the process does not exit with a listener pending: a command awaits the stream's drain before it returns, so no record is lost at exit (the silent-loss risk async adds; checked by a listener that is slow on purpose) |
| Isolation | a listener that throws is logged as a typed failure and does not stop the others or the writer (checked by a listener that throws) |

What happens today, per event (read from the code and the matrix; "next" is
what runs automatically after the move, which is nothing in every row except
the analyze gate):

| Event | Moves (from -> to) | Emitted by | What the command does around it | Logged as | Runs next, automatically |
|---|---|---|---|---|---|
| `setup` | noHandoff -> suggestInvestigating | `setup.dart:210` | writes `handoff.md` (archives a live one first); with sensitivity runs a scan | `logHandoffMove` (permissive: a move the table lacks is logged `rejected`, the command continues) | nothing |
| `saveUnconfirmed` | suggestInvestigating, debugInProgress -> same | `save.dart:71` | checkpoint to `archive/`, stamps the handoff | `logTransition` | nothing |
| `saveConfirmedExploring` | suggestInvestigating -> readyForSuggest | `save.dart:74` | same, plus appends the root cause to `skills.md` pending | `logTransition` | nothing |
| `saveConfirmedReady` | suggestInvestigating, readyForSuggest, readyForDebug, debugInProgress, needsSuggest -> readyForDebug | `suggest.dart:296` | after the model run, writes the handoff | `logTransition` | nothing |
| `debugStarted` | readyForDebug -> debugInProgress | `debug.dart:195` | written before any model call | `logTransition` | the debug pipeline itself |
| `debugBlocked` | debugInProgress -> needsSuggest | `debug.dart:182` | any failing debug step (including a plan that does not apply) writes it, then rethrows | `logTransition` | nothing; the user is told to run suggest |
| `suggestResumed` | needsSuggest -> suggestInvestigating | `suggest.dart:124` | suggest reads the debug notes first | `logTransition` | the suggest pipeline |
| `fixApplied` | readyForDebug, debugInProgress -> debugComplete | `debug.dart:335` | only after every planned file was written and each `.dart` file passed `dart analyze`; a failure restores the files and blocks instead | `logTransition` | nothing: it prints "run `claudart save`, then run tests"; no tests run |
| `rotated` | suggestInvestigating, readyForDebug, debugInProgress -> suggestInvestigating | `rotate.dart:199` | archives, runs the workspace after-fix build gate, seeds the next pending issue | `logHandoffMove` | the build gate (the one automatic check) |
| `rotatedEmpty` | same three -> noHandoff | `rotate.dart:180` | archives, resets to blank | `logHandoffMove` | nothing |
| `tornDown` | debugComplete -> noHandoff | `teardown.dart:336` | runs the analyzer model step, updates `skills.md`, archives, resets | `logHandoffMove` | nothing |
| `reminderSaved` | any live status -> noHandoff | `teardown.dart:339` | teardown from a status other than debugComplete: archives as a reminder | `logHandoffMove` | nothing |
| `killed` | any live status -> noHandoff | `kill.dart:155` | archives, does not touch `skills.md`, clears the lock | `logHandoffMove` | nothing |

`fixApplied` is an event, not a flag. The flag-like thing is the status it
lands in, `debugComplete`, which means "files written and analyze-clean, tests
not run"; `teardown` reads it to choose between `tornDown` and `reminderSaved`.
Because `debug` writes `debugStarted` first, it always applies `fixApplied`
from `debugInProgress`: the table's `readyForDebug --fixApplied` cell is never
produced as a move by current code. It is still used: `debug` checks it before
any model call to decide whether it may start (R8).

Decided by the owner: the stream is asynchronous. Still to decide: which
sequences start automatically after which state (for example, after
`fixApplied` run the tests; after `debugBlocked` open the suggest step); the
real logs show `suggest` tried from `debugComplete` twice (R2) and `kill` used
instead of `teardown` eight times (R3), so those two moves are the first
candidates to decide on evidence.
