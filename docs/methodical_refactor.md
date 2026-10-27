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
| S10 | `resolvedWithoutDebugHasNoStatus` | A handoff that is resolved without a debug (debug not applicable, or debug not used) has no way to be torn down: `tornDown` is legal only from `debugComplete`, which means a fix was applied. Owner's rule: teardown also when debug is not applicable, and in addition if debug isn't used | `session_state.dart` `tornDown` arm, owner direction | open, placeholder |
| S11 | `nothingVerifiesTheFix` | `debugComplete` means the planned files were written and each `.dart` file passed `dart analyze --no-fatal-warnings`; no test runs, and `debug` prints "run tests" for the user. The only verification command in the code is `afterFixCommand`, run by `rotate` as a gate, not by `debug` or `teardown`. So nothing today verifies that a fix works before a session can be torn down | `edit_files.dart:102`, `debug.dart:335-345`, `rotate.dart:156` | open, placeholder (H6) |

### Exits that leave no record

`save.dart:62,73`; `teardown.dart:75,138`; `kill.dart:103,114,126`;
`suggest.dart:101,231`; `setup.dart:100,104,164`; `rotate.dart:96,104,132`;
`launch.dart:49,80,137`; `logger.dart:229`. A save from a status with no save
move writes a checkpoint with no transition and no log. Status: open (E1, `exitsLeaveNoRecord`).

### Defaults and silent fallbacks

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| D1 | `defaultArmInLaunch` | `default:` arm | `launch.dart:158` | open |
| D2 | `wildcardArms` | Wildcard arms | `session_state.dart:29`; `failure_type.dart:82`; `claudart_command.dart:168,270`; `sync_check.dart:16,139`; `workspace_config.dart:41,61`; `chat_shell.dart:50`; `config.dart:80` | open; the four enum-subject arms were closed in Q1 (U1), the rest are on strings or ints |
| D3 | `corruptRegistryReadsEmpty` | A corrupt `registry.json` loaded as an empty registry, so a command could report "not registered" for a project that is. Closed in Q6: `Registry.load` throws `CorruptRegistryException` (`registryCorrupt`) for every unreadable shape, a missing or empty file is still an empty registry, and `doctor` reports the cause | `registry_test.dart` (six unreadable shapes), `doctor_test.dart` | closed (Q6) |
| D4 | `unreadableWorkspaceConfigDisablesStrictMode` | An unreadable `workspace.json` made `owner.strict` silently false in `suggest`, `debug`, `flow` and the hook. Closed in Q6: `WorkspaceConfig.load` throws `WorkspaceConfigUnreadableException` (new `FailureType.workspaceConfigUnreadable`, a config fault) for malformed JSON and JSON of the wrong shape; `suggest`, `debug`, `flow` and `link` stop before any model call or write; the hook never blocks an edit, so it advises as before and logs the failure by its type. The hook's fail-open choice is the assistant's and is recorded as open for the owner | `workspace_config_test.dart`, `suggest_test.dart`, `debug_test.dart`, `flow_test.dart`, `link_test.dart`, `hook_test.dart` | closed (Q6); hook fail-open awaiting the owner |
| D5 | `missingFileReadsEmpty` | Missing file reads as an empty string | `file_io.dart:41` | open |
| D6 | `homeDirectoryAssumed` | `HOME` assumed set | `paths.dart:75,79` | open |
| D7 | `tokenMapNotPersisted` | Token map updated but not persisted in setup and save | `setup.dart:191`; `save.dart:136` | open |
| D8 | `swallowedErrors` | Three catches dropped an error. Closed in Q6 for the token map: `TokenMap.load` throws `TokenMapUnreadableException` (new `FailureType.tokenMapUnreadable`) instead of loading an empty map that the next save would write back over every assigned token, and the failure boundary, which cannot abstract a message without the map, writes only the failure's label for a sensitive project. Accepted with a reason: `link.dart` `_detectProjectName` falls back to the folder name when `git remote` fails (a name guess, not a failure), and `session_ops.dart` `_safeDelete` ignores a failed delete while rolling back a failed close (the original failure is the one thrown) | `token_map_test.dart`, `failure_boundary_test.dart`, `link.dart:690`, `session_ops.dart:161` | closed (Q6) for the token map; two accepted |
| D9 | `suggestAppliesReadyWithoutConvergence` | `suggest` writes the model's `ROOT_CAUSE` with `tagOr`, which returns `_Not determined._` when the tag is missing, and then applies `saveConfirmedReady` anyway: the status says the root cause is locked while the handoff says it is not determined | `suggest.dart:271,291-296`, `xml_tags.dart:30` | open |
| D10 | `placeholderSpelledThreeWays` | The "no root cause" placeholder was `_Not yet determined._` in the template, `_Not determined._` from `tagOr`, and `debug` compared only the first, so the fallback reached the debug prompt as a real root cause; and six files each carried their own copy of the blank check. Closed in Q6: `HandoffPlaceholder` (`handoff_placeholder.dart`) owns the spellings and the one blank rule, `tagOr` falls back to it, the templates use its constants, and the copies are gone. A prompt-capture test sends each spelling through `debug` and fails against the old comparison | `handoff_placeholder_test.dart`, `debug_test.dart` (root cause in the prompt), `xml_tags_test.dart` | closed (Q6) |
| D11 | `repeatedLiteralsInLib` | The gate's first count: 174 string literals are repeated within a file across `lib/`, many of them JSON keys written once to read and once to write (`registry`, `workspace_config`, `archive_entry`, `pending_confirmation`) and status wire values. The no-bare-strings rule is far from met; the ratchet holds it at 175 | `check_duplicate_literals_test.dart` | open (reduced under Q6) |
| D12 | `sensitiveLoggerWithoutTokenMapWritesRaw` | `SessionLogger` abstracted text only when it held a token map, and 17 call sites built it by hand with a `sensitivityMode` bool; only 3 passed the map, so for a sensitive project the step log and error log (a failed step's reason) were written raw. Closed in Q6 as the first use of the typed-data shape: a sealed `LogProtection` (plain, abstracted with the map, label only) and one factory each; `SessionLogger.forEntry` picks from the registry entry (label only when the map is unreadable); the public constructor is gone; the failure boundary logs label only when the registry itself is unreadable; a scan fails if any call site builds the logger by hand | `logger_test.dart` (forEntry, labelOnly), `failure_boundary_test.dart`, `construction_funnel_test.dart` | closed (Q6) |
| D13 | `stringsWhereTypesBelong` | Objects carry `String` where a bool, enum, class, list or function would say what the value is. Measured in `lib/`: 135 `final String` fields in 44 files and 109 `required String` parameters. `SessionState` holds `attempted`, `changed` and `unresolved` as three raw strings that each hide a section with a placeholder; the same names recur as strings (`stepId` 7 times, `workspace`, `workspacePath` and `projectRoot` 12 times between them, `name`, `cause`, `label`), each one a concept that wants one type. The code written in this refactor does the same (`WorkspaceConfigUnreadableException(path, cause)`, `HandoffPlaceholder.isBlank(String)`). Dart 3.0 has no extension types, so a value type is a small class and a closed set is an enum | census in this section, `session_state.dart:239-256` | open, in progress: first typed section done (see the progress note); audited at Q2b and after every step |

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
| U1 | `wildcardArmUndetected` | A wildcard arm in an enum switch was caught by no tool. Closed in Q1: the lint `wildcard_arm_on_enum_switch` (error severity) fails on a default or `_` arm in a switch whose subject is an enum; it found four, in `claudart_command.dart`, `failure_type.dart`, `sync_check.dart` and one test, all now explicit variants. Wildcard arms on non-enum subjects (strings, ints) remain and belong to D2 | `claudart_lints.dart`, `make liveness` seed L6 | closed (Q1) |
| U2 | `bareStringComparisonUndetected` | A bare string compared with `==` was caught by no tool. Partly closed in Q1: the lint `enum_name_compared_to_string` fails on `enumValue.name == 'literal'` (none existed). A plain `String == 'literal'` is still unseen, deliberately: without the type owning the value the lint cannot tell a wire string from free text, and flagging every comparison would bury the real findings. Revisit when the wire edges are enum-owned (WireTag, field enums) | `claudart_lints.dart`, `make liveness` seeds L7, L8 | partly closed (Q1); plain-string case accepted with reason |
| U3 | `duplicateLiteralCheckAdvisory` | The duplicate-literal check only printed a nudge and exited 0. Closed in Q1: the same finding is now a ratchet test (`test/tool/check_duplicate_literals_test.dart`), and `make liveness` seed W1 trips it | `check_duplicate_literals_test.dart`, `make liveness` seed W1 | closed (Q1) |
| U4 | `newLogFileNameUndetected` | A new log file name written as a literal was not caught, because the ownership guard knew only the names `LogFile` already held. Closed in Q1: the guard now fails on any quoted `.jsonl` name that is not a `LogFile`, and the first run found a real one, `planner.jsonl` in `planner_log.dart`, now `LogFile.planner` | `literal_ownership_topology_test.dart`, `make liveness` seed T6 | closed (Q1) |

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
| M4 | `olderMutationSurvivors` | Mutation runs over the files this work touched found survivors in older, untouched lines, to be filed as one issue (not fixed inline, per the repo rule): `handoff_template` 33, `report` 40, `pipeline_executor` 37, `save` 26, `debug` 24, `rotate` 23, `kill` 21, `status` 17, `token_map` 10, `logger` 9, `workspace_config` 8, `teardown_utils` 7, `resume` 5, `sync_check` 3, and one each in `hook`, `failure_type` and `xml_tags`. `teardown` cannot be measured: it hangs the mutation tool | mutation runs, this document's progress notes | open, issue not yet filed |


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
| R9 | `killAllowedFromEveryLiveStatus` | The table allows `killed` from all six live statuses, including `debugComplete`. The owner's rule is that `kill` is only for a handoff that is not confirmed and `teardown` is for a root cause and fix that are completely done (teardown itself asks "confirmed resolved?": yes archives and updates `skills.md`, no saves a reminder). The table does not enforce that rule. The owner has since stated the rule in terms of knowledge transfer (see the placeholder section) | `session_state.dart` `killed` arm, `teardown.dart:96-110`, `kill.dart` doc | open, spec recorded as a placeholder |
| R10 | `statusDisagreesWithHandoffContent` | Of 179 archived handoffs and checkpoints, 17 say `suggest-investigating` while holding a real root cause and scope, and 1 says `ready-for-debug` with a placeholder root cause: about 10% have a status that does not follow the knowledge transfer in the handoff | the real workspace `archive/` | open |
| K1 | `workspaceKnowsNoFeatures` | The workspace records no Feature variants: `workspace.json` holds owner, project and session only, and `skills.md` is keyed by branch, category and files, not by Feature variant. Owner's direction: when a Feature variant is updated, the workspace should know which features exist in it. Scope not yet confirmed (derived from the project's enums, or declared) | `workspace.json`, `skills.md` | open, awaiting the owner's scope |
| K2 | `handoffHasNoType` | One `handoffTemplate` function renders every handoff (`setup.dart:179`, `rotate.dart:191`); the handoff records no type. `flow` classifies an `AgentCategory` in its own run and logs it, but never writes it into the handoff | `handoff_template.dart:3`, `flow.dart:226` | open |
| K3 | `scopeIsOneShapeForEveryKindOfWork` | `suggest` writes the same Scope sub-sections (files, entry points, classes, must-not-touch) for a bug, a feature, a refactor and a spike | `suggest.dart:277-284` | open |
| K4 | `knowledgeNotKeyedByFeature` | Knowledge is generic files plus one file per project; no file is keyed by a Feature variant, and `suggest` is told to read every generic file listed for the workspace, not the ones relevant to the handoff's feature | `knowledge/` layout, `setup_template.dart:31-39` | open |
| K5 | `threeCategoryTaxonomies` | `AgentCategory` (feature, bug, refactor, research, setup, gui), `TeardownCategory` (the skills categories) and the owner's handoff types (bug, feat, refactor, spike, story) are separate lists with no mapping between them | `categorization.dart:148`, `teardown.dart:195-209` | open |
| K6 | `ticketMetadataNotModeled` | Nothing in claudart models the ticket a handoff comes from. The owner's direction: the type of work will arrive as metadata on a sprint-board ticket (zedup owns the board), through an event-driven ticket flow, so `suggest` and `flow` are given a type instead of classifying one. Not yet vetted by the owner | owner direction, 2026-10-26 | open, placeholder (H1 to H4) |
| K7 | `debugDispositionNotRecorded` | Nothing in the handoff records whether debug is pending, done, not applicable or skipped: `debug` runs on whatever status allows it, and `teardown` asks the user. A type of work such as a spike should declare debug not applicable, and a decision not to use debug should be written down, not inferred | owner direction, `teardown.dart:96-110` | open, placeholder (belongs with H2) |

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
| S10 | drivesState x workspaceBound | existing |
| S11 | drivesState x processBound; untouched x processBound | existing |
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
| D11 | untouched x pure; untouched x workspaceBound; drivesState x processBound; observesState x workspaceBound | existing |
| D12 | observesState x fileSeam | existing |
| D13 | drivesState x workspaceBound; observesState x workspaceBound; untouched x workspaceBound; untouched x pure; drivesState x processBound | existing |
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
| M4 | drivesState x processBound; observesState x processBound; observesState x workspaceBound; untouched x workspaceBound; untouched x pure | existing |
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
| K6 | — | new: OwningPackage |
| K7 | drivesState x processBound; untouched x pure | existing |

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
| Q2 | `intendedBehaviorDecided` | M1, M2, R2, R3, R9, R10, S10, K7, D9, D10 | Q1 | the owner's decisions on handoff state become lifecycle scenarios that fail before the code agrees: when each move is wanted (`suggest` from `debugComplete`, `kill` versus `teardown` by knowledge transfer), the typed KT-converged value and the debug disposition recorded in the handoff, `suggest` not applying `saveConfirmedReady` without a root cause, one placeholder spelling; the undriven-cell ratchet reaches 0 or each remaining cell is marked unreachable with the reason; every state enhancement passes the convergence proof below |
| Q2b | `handoffObjectTyped` | D13, D9, D10, K3, K7 | Q2 | the handoff is one typed object whose fields say what they are: a typed section value instead of three strings for attempted, changed and unresolved, the KT-converged value and the debug disposition from Q2, and value types for the recurring strings (step id, workspace, project root, project name); constructors and method parameters take those types, so the one writer (Q3) and the transition stream (Q4) carry typed data from the start. A census of `String` fields and parameters is recorded before and after, and a ratchet stops it growing |
| Q3 | `oneWriterForStatus` | S2, S3, E1 | Q2 | a guard fails if `handoff.md` status is written anywhere but `applyHandoffEvent`; the seven state-driving command files go through it; every early exit writes a record (the census shows no unrecorded exit) |
| Q4 | `asynchronousTransitionStream` | S1, S6, S7, S8, H6 | Q3 | the totality, safety, termination, order, drain and isolation proofs of stage 3, each as a test; the logger is a subscriber and the `onTransition` callbacks are gone; `teardown` and the pipeline publish too; the first listener kind that calls `teardown` on converged, verified closure (headless and flow runs only) |
| Q5 | `logsCoverEveryCommand` | R1, R5, R7, S9 | Q4 | every command leaves an interaction record (a matrix over `ClaudartCommand`); a real run after a rebuild produces `steps.jsonl`; each log row names its schema version; `performance` has a writer or is removed |
| Q6 | `noSilentFallbacks` | D1 to D8 | Q1 | a corrupt registry, an unreadable `workspace.json` under strict mode, a missing `HOME`, an unpersisted token map and each wildcard arm become a typed failure or an explicit variant, each with the failing test first |
| Q7 | `measuredRedundancyRemoved` | B1 to B4, N1, N2, P1 | Q5 | `make spawn-census` and the call census show git spawned once per command, the registry parsed once, the log append not reading the log; the before and after counts are recorded here |
| Q8 | `familiesGrowWhereDataSaysSo` | S4, S8 and the proposed variants | Q4 | each proposed variant is added only with a file that needs it: `reactsToState` with the first listener, `TriggerSource` with agent-edit detection, `CodeTree` when tools and tests are scanned; the families doc and its drift test change with them |
| Q9 | `crossPackageTruth` | X1 to X9 | Q8 | one generated portal document across claudart, dartrix and zedup; the zedup compile break (X8) and the three contradicting plans are listed for their owners; no edit to dartrix or zedup from here |
| Q10 | `ticketClassificationPrepared` | K2 to K6 | Q4, and the current work complete | a placeholder `SprintTicket` (class or factory constructor) carries the type of work into the handoff; `HandoffTemplate` has one variant per type with Scope as a variant object; a handoff's data updates the Workspace Feature it is allocated to; `suggest` reads only that feature's knowledge. Designed in a parallel claudart session once the owner has vetted the ticket flow; nothing is built before then |
| Q11 | `fixVerifiedBeforeDone` | S11 | Q2, Q4 | `debug` runs the workspace `afterFixCommand` before it records the work as done and writes the evidence kind into the handoff; the five evidence scenarios of H6 pass; only verified evidence updates the workspace, and suggest-confirmed handoffs end as a reminder |

Progress (updated as steps finish):

- **Q1 `guardsThatSee`: done.** U1 closed (lint `wildcard_arm_on_enum_switch`;
  four enum-subject wildcard arms fixed), U2 partly closed (lint
  `enum_name_compared_to_string`; the plain-string case accepted with a reason),
  U3 closed (duplicate literals are a ratchet gate, 175 today, D11), U4 closed
  (a quoted `.jsonl` name must be a `LogFile`; it found `planner.jsonl`, now
  `LogFile.planner`). `make liveness`: 18 of 19 seeds caught. Mutation on the
  touched lib files: no survivor in a line this step changed; older survivors
  are `failure_type.dart` line 119 and `sync_check.dart` lines 30, 31 and 126,
  to be filed as an issue with the other pre-existing ones, not fixed here.

- **Q6 `noSilentFallbacks`: in progress.** D3, D4, D8, D10 and D12 closed (see the register).
  Mutation on the touched files: no survivor in a line this step changed;
  older survivors are `workspace_config.dart` lines 88 and 91, `hook.dart` line
  133 and `failure_type.dart` line 124, for the issue of pre-existing ones.
  Token map slice: no survivor in a line it changed (a first run found one in the new exception, fixed with a test); older survivors are `token_map.dart` lines 100, 105, 132 to 134 and 143 and `failure_type.dart` line 128. Placeholder slice: no survivor remains in a line it changed, except where the run could not measure: `teardown.dart` hangs the mutation tool (the same upstream limitation as issue #77; its one changed line is the swapped blank check, covered by the teardown tests), and `debug.dart` was not run (its changed condition is covered by the prompt-capture test, shown to fail against the old comparison). A first run left two changed lines of `kill.dart` uncovered; tests for the attempted and changed work lines fixed that. Older survivors are listed per file in the run output, for the issue of pre-existing ones. Logger slice (D12): mutation found no survivor in a changed line; the new `log_protection.dart` and the failure boundary have none; `logger.dart` has 9 older (down from 13). Still open under Q6: D1, D2 (non-enum arms), D5, D6, D7, D11, D13.

- **Q2b `handoffObjectTyped`, first part: done.** Q2b splits in two: the part
  that needs only Q1 (typing what already exists) and the part that needs Q2's
  decisions (the KT-converged value, the debug disposition). Done: `HandoffSection`
  (`handoff_section.dart`) holds a section's text and knows whether it is blank;
  `SessionState`'s five section fields (`bug`, `rootCause`, `attempted`,
  `changed`, `unresolved`) are now that type, so a stray string no longer
  compiles there and every blank check is one getter. `String` fields in `lib/`:
  135 to 131 (the five fields became one type; the new class adds one). Mutation: no survivor
  in a changed line (a first run found the status command's bug and root cause
  lines unchecked; a test now pins them). Still to do for the first part: value
  types for the recurring strings (step id, workspace, project root, project
  name); the second part waits for Q2.

Why this order: Q1 first because every later step needs a tool that would
notice a regression. Q2 before any code because the real logs show behavior
the table does not describe (R2, R3), and only the owner can say which is
intended. Q3 before Q4 because a stream of transitions is only complete if one
writer publishes them. Q6 depends only on Q1 and can run beside Q3 to Q5.

### The shape of typed data (owner's direction)

Recorded so every step that adds or changes an object follows it. The owner's
words, then how the assistant reads them (the reading is marked; confirm or
correct it).

> Enums, typedefs, bools and the like enforce the validity of the required
> types that are passed. This should cut down the codebase, mitigating existing
> redundancies, to fit our goal to funnel from generics to specifics per
> utilization. Use factory constructors when possible, switching off the enum
> they are based on; abstract classes first, depending on the utilization.
> Templates should check this type, so the scoped data is passed and the
> AgentFlow is tightened per the return type of the future or function. That is
> best practice at its finest.

Reading:

- **Funnel from generic to specific.** A value starts as the narrowest type that
  says what it is. A `String`, `Map` or nullable that stands in for a closed
  set, a flag, a collection or a function is replaced by an enum, a `bool`, a
  list, a typedef or a class.
- **Abstract first, then variants.** Where the variants carry different data, a
  `sealed` (or `base`) class comes first and the variants extend it, as
  `PipelineEvent` and `StepRoute` already do with a kind enum beside them. Where
  they carry none, an enum is enough.
- **A factory constructor switches off the enum it is based on.** One entry
  point per kind, with an exhaustive switch and no default arm, so a new variant
  fails to compile until it is built.
- **Templates take the typed variant, not loose data.** A template function's
  parameter is the variant (or the typed object), so passing the wrong scope
  fails at compile time and the AgentFlow's step output type follows from the
  type the function or future returns.
- **One construction path per concept.** Where many call sites build the same
  object by hand, one factory builds it and the public generative constructor
  goes away; the redundancy and the chance to build it wrongly go with it.

First application: D12. `SessionLogger` was built by hand at 17 call sites
with `sensitivityMode` (a bool) and an optional token map, and only 3 passed
the map, so for a sensitive project most logs were written without
abstraction. The shape replaces that with a sealed protection type (plain,
abstracted with a token map, label only) and one factory per case, built from
the registry entry.

### Proof that a handoff state enhancement converges

Applies to any change to what the handoff records or how its status moves: a
new status, the debug disposition, the evidence kind, the KT-converged value,
the Scope variants. A change is not done until every line below holds, each as
a test written before the change:

| Check | What it proves |
|---|---|
| Totality | every status x event cell is decided in an exhaustive switch with no default arm; a new variant fails to compile until it is |
| Safety | every move a listener or command can request is legal from the status it lands in, over all cells |
| Termination | the relation event -> events a listener may return is acyclic, so a chain is at most one hop per event |
| Status follows content | no converged status holds an unconverged KT and no unconverged status holds a converged one: asserted on the lifecycle scenarios and run over the real archived handoffs, where today it disagrees in about 10% (R10); the target is zero |
| Shape | a new object follows the shape above: abstract first, a factory that switches exhaustively on its enum, templates and functions taking the typed variant; no new public constructor where one factory can build it |
| Typed data | the fields and parameters the change adds are typed values (enum, class, bool, list, function), not `String`, unless the string is genuinely free text; the census of `String` fields and parameters does not grow |
| Evidence matrix | each row of the H6 matrix is a scenario whose expected exit is written before the code, and whose logged moves match the consumer view |
| Real-log replay | the real `transitions.jsonl` moves (44 on this machine) replay through the new table and every one that was legal still is, so no real session becomes illegal |
| Ratchet | the undriven-cell count does not grow, and the gap register test still places every gap in a family or a proposed variant |

Convergence here means: the checks above all pass on the final table, so a
handoff cannot reach a state the table does not describe, cannot end in a state
that disagrees with its content, and cannot trigger a chain that does not end.

### Placeholders (the owner's architecture, not designed yet)

Recorded so the work in progress leaves room for it. Each row is the owner's
direction in outline, not a design; none is built, and the two open decisions
below wait on it.

| Id | Name | Outline | Depends on |
|---|---|---|---|
| H1 | `sprintTicket` | for now, work is allocated into a handoff as a `SprintTicket` (a class, or a factory constructor); it carries the ticket's metadata: the type of work now, the Workspace Feature later | none |
| H2 | `handoffTemplateVariants` | `template(type, handoff) => HandoffTemplate.variant(metadata)`: one variant per type of work, switched on the type the handoff is scoped to; the Scope section is an object on the variant, not one shared shape | H1 |
| H3 | `workspaceFeatureUpdatedByHandoff` | the data captured per handoff updates the Workspace Feature the handoff is allocated to; knowledge is organized per feature, and `suggest` is given only the knowledge for that feature | H2, K1 |
| H4 | `ticketEventFlow` | ticket handling driven by events: the sprint board (zedup) communicates the ticket's metadata, so `suggest` and `flow`, invoked asynchronously, already know the type of work | Q4, H1 |
| H5 | `endSessionByKnowledgeTransfer` | a session ends by what the handoff says, not by which command the user chose: resolved (converged KT and debug done, not applicable or skipped) means `save` then `teardown`, which updates the workspace; converged with debug pending is a reminder; not confirmed is `kill`; see the section below | H2, D9, D10, S10, K7 |
| H6 | `convergenceClosesWithVerifiedEvidence` | when the flow converges it calls `teardown` itself, carrying the evidence that closed the KT: the fix was verified by `debug` after testing, or `suggest` confirmed readiness and debug is not being run. Closure is verified by an agent, and where the flow calls for debug, `debug` does the verifying | H5, Q4, S11 |

Open decisions, deferred by the owner until the ticket flow is vetted: the
single list of handoff types (the owner's bug, feat, refactor, spike, story
against `AgentCategory` and the teardown categories, K5) and where the type is
chosen and whether it can change (K2). Until then `setup` and `flow` keep
classifying as they do today.

### Placeholder: ending a session by knowledge transfer (work in progress)

**Status: placeholder.** The owner's rule is recorded below in the owner's own
words. The tables under it are the assistant's reading of that rule against
today's statuses. Nothing here is enforced or tested yet, no transition in
`HandoffStatus.after` has been changed, and every "not implemented" line is a
gap in the register.

The owner's spec, as given (first statement, its refinement, then a correction):

> Verify the topology based on whether the handoff specifies the KT
> (knowledge transfer): when the suggest process determines convergence, that
> is, defines the root cause and the solution, even when suggest or flow
> communicates the resolution, we can teardown; otherwise kill. This is not
> implicit. Even when the debug session has not been handed over: save, then
> teardown.
>
> The only time kill should be used is when the handoff isn't confirmed.
> Teardown is for when the root cause and the fix are completely done.
>
> Teardown is only used when the handoff confirms debug is not applicable,
> which suggests the handoff is sufficient for KT to the workspace's
> categorized Feature (selection, metadata arbitration). Teardown has a flow
> for updating the respective attributes of the workspace. The goal is that
> arbitrary handoffs recognize the scoped workspace attributes and ramp up
> more efficiently. This further defines the dependencies per analysis and
> debugging.
>
> Correction: not only when debug is not applicable; in addition, if debug
> isn't used.

How the statements fit together (the assistant's reading, to be confirmed):

- A session can end three ways, not two, and the handoff decides which.
- Debug has a *disposition* recorded in the handoff (a placeholder name and
  value set, the assistant's): `pending` (applicable, not yet run), `done`
  (the fix was applied), `notApplicable` (the type of work has no debug, such as
  a spike) and `skipped` (debug applies but is not going to be used). `skipped`
  is an explicit decision written into the handoff, never inferred from debug
  simply not having run.
- **`teardown`** is for a handoff that is *resolved*: converged KT and a debug
  disposition of `done`, `notApplicable` or `skipped`. The handoff is then
  sufficient KT, and `teardown` is the step that updates the workspace's
  attributes (today `skills.md`; the Workspace Feature once H3 exists).
- **`reminderSaved`** (the existing "save as a reminder to resume later" path)
  is for converged KT with debug `pending`: nothing is resolved yet, so the
  workspace is not updated and the pending entry stays.
- **`kill`** is for a handoff that is not confirmed.
- "Not implicit" is read as: the rule is checked from the handoff, not assumed
  from the command or the status line; that is why `skipped` must be recorded.

What depends on what, per analysis and debugging (placeholder):

| Step | Needs | Produces | Updates the workspace |
|---|---|---|---|
| analysis (`suggest`, `flow`) | a handoff of a type of work | KT: root cause and solution (the Scope variant, H2); converged or not | no |
| `debug` | converged KT, and debug disposition `pending` | the fix: `debugComplete`, disposition `done` | no |
| `teardown` | resolved: converged KT and debug disposition `done`, `notApplicable` or `skipped` | archive entry and the workspace update | yes: skills now, Workspace Feature later (H3) |
| `reminderSaved` | converged KT, debug disposition `pending` | archive reminder, pending entry kept | no |
| `kill` | KT not converged | archive only | no |

Placeholder mapping onto the statuses that exist today:

| Status | KT | Debug disposition | Ends with | Today |
|---|---|---|---|---|
| `suggestInvestigating` | not converged | not reached | `kill` | `kill` and a reminder both legal |
| `needsSuggest` | not converged (a blocked debug put the root cause in doubt) | blocked | `kill` | both legal |
| `readyForSuggest` | converged | `pending`, or `skipped` / `notApplicable` once recorded | `pending`: reminder or continue; otherwise `save`, then `teardown` | `teardown` writes a reminder; `tornDown` not legal |
| `readyForDebug` | converged | same | same | same |
| `debugInProgress` | converged | `pending` (a run is mid-way), or `skipped` | same | same |
| `debugComplete` | converged, fix applied | `done` | `save`, then `teardown` | `tornDown` legal; `kill` also legal |
| none yet | converged, resolved by analysis | `notApplicable` | `save`, then `teardown` | **no status says this** (S10) |
| `noHandoff` | no session | none | none | none |

The row marked "none yet" is the main structural finding. `teardown` is legal
only from `debugComplete`, so a handoff resolved by analysis, or one where
debug was skipped, cannot be torn down at all. Closing that needs the debug
disposition recorded in the handoff (K7), and then either a `HandoffStatus`
variant for "resolved without debug" or `teardown` becoming legal from the
converged statuses when the disposition allows it. Which of the two is
open; the names are the assistant's placeholders, not the owner's.

Not implemented, each recorded in the register: no typed KT-converged value
exists on the handoff object (D9, D10, R10); `suggest` can apply
`saveConfirmedReady` without a root cause (D9); `tornDown` is legal only from
`debugComplete` and `killed` from every live status (R9); `teardown` decides
"resolved" by a yes or no answer, not by the handoff (R9); there is no status
for a handoff resolved without debug (S10) and no record of whether debug is
pending, done, not applicable or skipped (K7); `teardown` updates `skills.md` only, not a Workspace Feature
(K1); the Scope shape is one for every kind of work (K3).

#### Convergence closes with recorded evidence (owner's idea, placeholder)

The owner's direction: when the AgentFlow converges it calls `teardown`,
indicating the fix has been verified, either by `debug` after testing, or by
`suggest` confirming readiness (`readyForDebug`) with debug not being run. The
closure to the KT should be verified by the agent, and where the flow calls for
debug, `debug` handles it. To be tested; nothing is built.

The assistant's reading, with the parts that are its own marked:

- The evidence is recorded in the handoff, as the debug disposition is
  (placeholder values, the assistant's): verified by a `debug` run that passed
  its checks, or confirmed by `suggest` with no verification run. They are
  different trust levels and should stay distinguishable in the knowledge that
  `teardown` writes.
- The check `debug` runs today is only `dart analyze` on the written files (S11);
  the existing `afterFixCommand` gate is the candidate verification, run by
  `debug` before it records the disposition.
- The call to `teardown` is a reaction to a transition, which is what the
  stage 3 listeners are for; `teardown` includes a model step, which is why the
  stream is asynchronous.

A test plan, written before any code, as a matrix of evidence against the
expected exit (each row a lifecycle scenario):

| Evidence when the flow converges | Expected |
|---|---|
| `debug` ran and its verification passed | `teardown` runs, workspace updated |
| `debug` ran and its verification failed | no `teardown`; status `needsSuggest`; failure logged |
| `suggest` confirmed, debug skipped, recorded | `teardown` runs, evidence recorded as suggest-confirmed |
| `suggest` confirmed, nothing recorded about debug | no `teardown`; reminder |
| converged by the flow with no evidence at all | no `teardown`; stays open |

Agreed in principle by the owner (to be confirmed when the tests are written):
the automatic `teardown` is for headless and flow runs only, interactive runs
keep the confirm; only verified evidence updates the workspace, and a
suggest-confirmed handoff ends as a reminder until the owner decides otherwise.

Open, and left open on purpose: whether `constraints` are part of a converged
KT; what `teardown` writes when no fix was applied (today it reads changed
files, and an analysis-only session has none); the name and place of the
analysis-resolved status; and the table changes themselves, which are written
test-first under Q2 and Q3 once the owner has confirmed this reading.

## Stage records

Each entry states the pass condition first, then the observed result.

### Stage 0.2 - tool liveness

Pass condition: for every tool and every defect shape it claims to catch, a
seeded defect in a scratch copy of the repo is reported. A defect it does not
report is a finding. The working tree is never seeded; the harness is
`tool/refactor_audit/liveness.sh` (`make liveness`) and copies the repo first.

Observed at first (18 seeds): 15 caught, 3 missed. After Q1 (19 seeds, the plain-string case added): 18 caught, 1 missed (a twentieth seed, the construction funnel, was added with D12 and is caught), the plain-string comparison, accepted with a reason (U2). The duplicate-literal seed is caught by a gate, not a nudge. The 18th seed (T7) is the call
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
| L6 | `wildcardArmOnEnumSwitch` | custom_lint `wildcard_arm_on_enum_switch` | wildcard arm on an enum switch | caught (was missed; closed in Q1) |
| L7 | `enumNameComparedToString` | custom_lint `enum_name_compared_to_string` | enum name compared to a string literal | caught (was missed; closed in Q1) |
| L8 | `plainStringComparedToLiteral` | any | plain `String` compared to a literal with `==` | **missed** (accepted, see U2) |
| W1 | `sameFileDuplicateLiteral` | `check_duplicate_literals` | same-file duplicate literal | caught (advisory, exit 0); caught by the gate after Q1 |
| T1 | `logFileNameLiteralInLib` | literal ownership guard | log file name literal in `lib/` | caught |
| T2 | `testTitleNamingTypeAsText` | literal ownership guard | test title naming a type as text | caught |
| T3 | `handoffDocDrift` | handoff topology test | generated doc drift | caught |
| T4 | `modelIdLiteralInLib` | model metadata guard | model id literal in `lib/` | caught |
| T5 | `environmentDocDrift` | environment topology test | generated doc drift | caught |
| T7 | `callCensusDocDrift` | call census test | generated doc drift | caught |
| T6 | `logNameLiteralNotInLogFile` | literal ownership guard | log name literal not yet in `LogFile` | caught (was missed; closed in Q1) |
| F1 | `loggerBuiltByHandOutsideFactories` | construction funnel test | a `SessionLogger(` call outside `logger.dart` | caught |
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
