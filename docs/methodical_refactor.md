# Methodical refactor

How a refactor is run when every step must be proven and nothing may be assumed.
This document is the feature's record: the stage sequence, the gap register, and
what each stage proved. It is written as the work happens, so it shows how the
work was actually done.

The approved plan is the source of the stage order (Phases 0 to 6). The
reasoning behind a stage is in `docs/session_log.md`; the roadmap entry is in
`PLAN.md`.

## Where we are (rendered 2026-10-28)

Branch `claudart/enum-matrix-architecture`, all local, nothing pushed; the suite,
`custom_lint` and the analyzer baseline (18) hold at every commit. This section is
the one place that says what is done and what is next, so it survives a lost
context; the register below holds the evidence.

| Step | Name | State |
|---|---|---|
| Phases 0 to 2 | tool liveness, census, families, status x event matrix | done |
| Q1 | `guardsThatSee` | done |
| Q2 | `intendedBehaviorDecided` | done, provisional: `suggest` rejection text, `kill` warning and record, knowledge-transfer value, debug disposition, the `tornDown` table change (S10). Open: `notApplicable` has no writer (waits on H2) |
| Q2b | `handoffObjectTyped` | first part partly done (`HandoffSection`); the value types for step id, workspace, project root, project name remain |
| Q6 | `noSilentFallbacks` | done except D11 (repeated literals), D13 (typed values) and D16, which fold into Q12, Q17 |
| Q12 | `shapeTopologyAndBases` | done 2026-10-30: I1 analyzer test built, three pairs consolidated, ratchet 0; the other shape-based bases wait for the Q15 enum data |
| Q13 | `seamBundle` | done 2026-10-30: `CommandSeams` (io, projectRootOverride, exitFn, confirmFn, askFn, pickFn) replaces the loose parameters of the nine seam-heavy commands; ratchet 0; the other commands and the runner, executor and mode parameters stay per command |
| Q14 | `oneSourcePerDatum` | done for the environment, home directory, processes, git executable and the project lookup (`lookupProject`, `requireProject`; six files with their own lookup are in a ledger with the reason); credentials, settings and `workspace.json` access remain |
| Q15 | `enumFactsAsData` | not started |
| Q16 | `folderLayout` | not started |
| Q17 | `userTextFromConfig` | not started |
| Q3, Q4, Q5 | one writer, the asynchronous stream, logs for every command | not started; recommended to wait for Q12 to Q15: writing the writer and the stream on today's duplicated seams and per-variant switches would mean writing them twice |
| Q7 | `measuredRedundancyRemoved` | last, by design |
| Q8 to Q11 | families, cross-package, ticket classification, verified fix | not started; Q10 waits on the owner vetting the ticket flow |

Provisional decisions awaiting the owner's confirmation: `suggest` from
`debugComplete` is rejected with a next step; the hook stays fail-open and logged;
the `kill` rule is a warning until verified-closure `teardown` exists; the
`readyForDebug --fixApplied` cell stays as `debug`'s start check; `tornDown` is
legal from the four statuses that expect a complete transfer.

Open owner questions: the single list of handoff types and where the type is
chosen (K2, K5, deferred until the ticket flow is vetted); the Workspace Feature
scope (K1); whether dropping an unknown stack or agent entry in `workspace.json`
is intended (D16); and the thresholds k and theta for the shape invariant I1.

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
| S7 | `teardownPipelineUnlogged` | The `teardown` analyzer pipeline had no log subscriber, so a `teardown` run left no step record. Closed: `runTeardown` subscribes its logger to the executor's events like `suggest`, `debug` and `flow` (and `ClaudartCommand.recordsStepModels` now says so, checked against the source). The subscription is still dropped after the run (the stream is not async yet; Q4) | `teardown.dart`, `claudart_command_test.dart` | closed for teardown (Q4 still owns the stream) |
| S8 | `pipelineStateMachineUndeclared` | Pipeline FSM exists only as a comment | `pipeline_event.dart:3-24` | open |
| S9 | `performanceLogHasNoWriter` | `LogFile.performance` has no writer | `logger.dart:326` | open |
| S10 | `resolvedWithoutDebugHasNoStatus` | A handoff resolved without a debug (debug not used) could not be torn down: `tornDown` was legal only from `debugComplete`. Closed in Q2 (provisional): `tornDown` is now legal from `readyForSuggest`, `readyForDebug`, `debugInProgress` and `debugComplete`, exactly the statuses that expect a complete knowledge transfer (proof P14); `teardown` asks "Debug did not run for this handoff. Record it as skipped?", writes `skipped` into the archived handoff on yes, and treats no as not resolved (nothing is torn down). A handoff resolved because debug does not apply (`notApplicable`) still has no writer, so that case waits on the type of work (H2) | `session_state.dart`, `teardown.dart`, `teardown_test.dart`, `transition_proofs_test.dart` | closed for skipped debug (Q2); notApplicable open |
| S11 | `nothingVerifiesTheFix` | `debugComplete` means the planned files were written and each `.dart` file passed `dart analyze --no-fatal-warnings`; no test runs, and `debug` prints "run tests" for the user. The only verification command in the code is `afterFixCommand`, run by `rotate` as a gate, not by `debug` or `teardown`. So nothing today verifies that a fix works before a session can be torn down | `edit_files.dart:102`, `debug.dart:335-345`, `rotate.dart:156` | open, placeholder (H6) |
| S12 | `teardownSpawnedTheRealModelInTests` | `runTeardown` built its own executor, so 37 test call sites (34 in `teardown_test.dart`, the lifecycle scenarios, the smoke test) started the real `claude` process. They passed because the CLI failed fast under `dart test` (2.5 s with `claude` on `PATH`, 1.4 s without), but on a machine where it is signed in they could spend model calls. Closed: `runTeardown` takes an `executor`, every test passes a fake that never answers, and a guard fails if a test call omits it | `fake_executors.dart`, `model_seam_guard_test.dart` | closed |
| S13 | `setupScanIgnoredItsInjectedIo` | In a sensitive project `setup` called `runScan` without passing its own io, so the scan read and wrote the real filesystem even when the command was given an in-memory one (in a test it tried to create `/workspaces`). Found by the new sensitive-setup test; closed by passing `io`. A new instrument, `make leak-check`, runs the whole suite with HOME and the workspace root pointed at empty temp directories and fails if any test leaves a file: it passes now, and a seeded leaking test trips it | `setup.dart`, `write_leak_check.sh` | closed |

### Exits that leave no record

`save.dart:62,73`; `teardown.dart:75,138`; `kill.dart:103,114,126`;
`suggest.dart:101,231`; `setup.dart:100,104,164`; `rotate.dart:96,104,132`;
`launch.dart:49,80,137`; `logger.dart:229`. A save from a status with no save
move writes a checkpoint with no transition and no log. Status: open (E1, `exitsLeaveNoRecord`).

### Defaults and silent fallbacks

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| D1 | `defaultArmInLaunch` | `launch.dart` picked from three menus by comparing an index to `static const` ints (`ActiveMenu.resume = 0`), and one switch ended in `default: // back — no-op`, so any index nothing handled was silently ignored. Closed in Q6 as an application of the typed-data shape: each menu is an enum that owns its labels (in the order shown), `_choose` turns the pick back into the enum, and the switch names every variant with no default. A first run showed the cost of the old form: a launch test had been answering a fresh-workspace menu with an active-session constant (2 of 0..1), which the ints let through unnoticed and the enum rejects | `launch.dart`, `launch_test.dart` | closed (Q6) |
| D2 | `wildcardArms` | Wildcard arms on non-enum subjects. Fixed (Q6): `ClaudartOperation.fromString` took any unknown name for `test` (so `claudart preflight tset` ran the test check and passed), `WorkspaceRole.fromString` took any unknown role for `contributor`, and `ProofNotation.fromString` any unknown notation for `generic`; each now returns null for a name it does not know, `preflight` says "Unknown operation" and exits 1, an unknown role or notation in `workspace.json` makes the file unreadable (the typed D4 failure), and the `link` wizard names the default it applies. Accepted with reasons, each an explicit complement by design: `HandoffStatus.fromString` (`_ => unknown`: `unknown` is a declared variant for an unreadable status line), `ClaudartCommand.fromString` (`_ => null`: not a command), `ChatCommand.parse` (`_ => help`: an unrecognised slash word lists the commands), and the step timeout in `config.dart` (`_ => null`: a value that is not a non-negative integer is unset) | `sync_check_test.dart`, `preflight_cmd_test.dart`, `workspace_config_test.dart`, `link_test.dart` | closed (Q6); four accepted |
| D3 | `corruptRegistryReadsEmpty` | A corrupt `registry.json` loaded as an empty registry, so a command could report "not registered" for a project that is. Closed in Q6: `Registry.load` throws `CorruptRegistryException` (`registryCorrupt`) for every unreadable shape, a missing or empty file is still an empty registry, and `doctor` reports the cause | `registry_test.dart` (six unreadable shapes), `doctor_test.dart` | closed (Q6) |
| D4 | `unreadableWorkspaceConfigDisablesStrictMode` | An unreadable `workspace.json` made `owner.strict` silently false in `suggest`, `debug`, `flow` and the hook. Closed in Q6: `WorkspaceConfig.load` throws `WorkspaceConfigUnreadableException` (new `FailureType.workspaceConfigUnreadable`, a config fault) for malformed JSON and JSON of the wrong shape; `suggest`, `debug`, `flow` and `link` stop before any model call or write; the hook never blocks an edit, so it advises as before and logs the failure by its type. The hook's fail-open choice is the assistant's and is recorded as open for the owner | `workspace_config_test.dart`, `suggest_test.dart`, `debug_test.dart`, `flow_test.dart`, `link_test.dart`, `hook_test.dart` | closed (Q6); hook fail-open awaiting the owner |
| D5 | `missingFileReadsEmpty` | `RealFileIO.read` returns an empty string for a file that does not exist, so a missing file and an empty one look the same to a reader. Accepted with a reason: it is the documented contract of the seam, every command that needs to tell them apart already checks `fileExists` first, and the readers where it mattered (registry, workspace config, token map) now treat an unreadable file as a typed failure while still treating empty or missing as "none yet"; changing the seam to throw would touch ~100 call sites for no case that is still wrong | `file_io.dart:41`, D3, D4, D8 | accepted (reason recorded)
| D6 | `homeDirectoryAssumed` | `workspacesRoot` read `Platform.environment['HOME']!`, so an unset `HOME` was a null-check error with no message. Closed in Q6: the rules are the pure `workspacesRootFor(environment)`, and a needed `HOME` that is not set is a typed `homeDirectoryUnset` failure that says what to set; seven cases are tested, including an absolute `CLAUDART_WORKSPACE` needing no `HOME` | `paths_test.dart`, `failure_type_test.dart` | closed (Q6)
| D7 | `tokenMapNotPersisted` | `setup` and `save` abstracted text with a token map but never saved it, and `save` loaded a fresh map for each text, so two names of one kind both became `Bloc:A` (a collision) and the next run reassigned tokens. Closed in Q6: `abstractTexts` uses one map per call and saves it when it gained a token; the same step found `setup` calling its scan without its injected io (S13) | `abstractor.dart`, `save_test.dart`, `setup_test.dart` | closed (Q6)
| D8 | `swallowedErrors` | Three catches dropped an error. Closed in Q6 for the token map: `TokenMap.load` throws `TokenMapUnreadableException` (new `FailureType.tokenMapUnreadable`) instead of loading an empty map that the next save would write back over every assigned token, and the failure boundary, which cannot abstract a message without the map, writes only the failure's label for a sensitive project. Accepted with a reason: `link.dart` `_detectProjectName` falls back to the folder name when `git remote` fails (a name guess, not a failure), and `session_ops.dart` `_safeDelete` ignores a failed delete while rolling back a failed close (the original failure is the one thrown) | `token_map_test.dart`, `failure_boundary_test.dart`, `link.dart:690`, `session_ops.dart:161` | closed (Q6) for the token map; two accepted |
| D9 | `suggestAppliesReadyWithoutConvergence` | `suggest` wrote the model's `ROOT_CAUSE` with `tagOr`, which returned a placeholder when the tag was missing, and then applied `saveConfirmedReady` anyway. Closed in Q2: the write is gated on a root cause and files in play; otherwise nothing is written, the status stays, and a typed `knowledgeTransferNotConverged` failure (with its own suggested action) is thrown before any change. Tests cover no tags, a root cause with no scope, and the unchanged handoff and status | `suggest_test.dart`, `failure_type_test.dart` | closed (Q2) |
| D10 | `placeholderSpelledThreeWays` | The "no root cause" placeholder was `_Not yet determined._` in the template, `_Not determined._` from `tagOr`, and `debug` compared only the first, so the fallback reached the debug prompt as a real root cause; and six files each carried their own copy of the blank check. Closed in Q6: `HandoffPlaceholder` (`handoff_placeholder.dart`) owns the spellings and the one blank rule, `tagOr` falls back to it, the templates use its constants, and the copies are gone. A prompt-capture test sends each spelling through `debug` and fails against the old comparison | `handoff_placeholder_test.dart`, `debug_test.dart` (root cause in the prompt), `xml_tags_test.dart` | closed (Q6) |
| D11 | `repeatedLiteralsInLib` | The gate's first count: 174 string literals are repeated within a file across `lib/`, many of them JSON keys written once to read and once to write (`registry`, `workspace_config`, `archive_entry`, `pending_confirmation`) and status wire values. The no-bare-strings rule is far from met; the ratchet holds it at 175 | `check_duplicate_literals_test.dart` | open (reduced under Q6) |
| D12 | `sensitiveLoggerWithoutTokenMapWritesRaw` | `SessionLogger` abstracted text only when it held a token map, and 17 call sites built it by hand with a `sensitivityMode` bool; only 3 passed the map, so for a sensitive project the step log and error log (a failed step's reason) were written raw. Closed in Q6 as the first use of the typed-data shape: a sealed `LogProtection` (plain, abstracted with the map, label only) and one factory each; `SessionLogger.forEntry` picks from the registry entry (label only when the map is unreadable); the public constructor is gone; the failure boundary logs label only when the registry itself is unreadable; a scan fails if any call site builds the logger by hand | `logger_test.dart` (forEntry, labelOnly), `failure_boundary_test.dart`, `construction_funnel_test.dart` | closed (Q6) |
| D13 | `stringsWhereTypesBelong` | Objects carry `String` where a bool, enum, class, list or function would say what the value is. Measured in `lib/`: 135 `final String` fields in 44 files and 109 `required String` parameters. `SessionState` holds `attempted`, `changed` and `unresolved` as three raw strings that each hide a section with a placeholder; the same names recur as strings (`stepId` 7 times, `workspace`, `workspacePath` and `projectRoot` 12 times between them, `name`, `cause`, `label`), each one a concept that wants one type. The code written in this refactor does the same (`WorkspaceConfigUnreadableException(path, cause)`, `HandoffPlaceholder.isBlank(String)`). Dart 3.0 has no extension types, so a value type is a small class and a closed set is an enum | census in this section, `session_state.dart:239-256` | open, in progress: first typed section done (see the progress note); audited at Q2b and after every step |
| D16 | `unknownStackAndAgentEntriesDropped` | `workspace.json` parsing drops a stack or agent entry it does not recognise (`.whereType<StackType>()`, `.whereType<AgentFlow>()`), so a typo silently narrows the workspace's declared stack or agents. Found while closing D2 and not changed: dropping may be intended for forward compatibility, which is the owner's call | `workspace_config.dart` project and session parsing | open |
| Y1 | `sharedShapesNotInherited` | Classes that hold the same properties are written separately instead of a base class holding them and variants extending it. Measured by the analyzer pass (`test/helpers/class_shapes.dart`, ratchet in `shape_consolidation_test.dart`): three pairs, `Action`/`Result`, `StepResult`/`AgentCompleted` and `WorkspaceSummary`/`RegistryEntry`; the earlier regex count of 67 was wrong. Closed 2026-10-30: `SubtaskResponse` base, `StepTelemetry` held once by both, `WorkspaceSummary` holds its `RegistryEntry`; ratchet 0. | `agent_response.dart`, `pipeline_event.dart`, `workspace_config.dart`; measurement script in this section | open |
| Y2 | `seamParametersRepeatedPerFunction` | The same injected seams are redeclared on every command function instead of one bundle passed down: `FileIO? io` 66 declarations in 43 files, `projectRootOverride` 22 files, `exitFn` 19, `pickFn` 18, `promptFn` 16, `confirmFn` 9, `ProcessRunner? runner` 9 | `lib/commands/*.dart`, `lib/session/*.dart` | open |
| Y3 | `dataSourcesAccessedFromManyFiles` | One source of truth per external datum is not enforced: `Platform.environment` is read in 9 files, `Process.run/start` in 9, the git helpers (`detectGitContext`, `readGitConfig`, `resolveProjectRoot`) are used 44 times in 24 files, and the credential and settings reads (`~/.claude/settings.json`, provider env) sit in more than one file | `bin/claudart.dart`, `lib/commands/*`, `lib/providers/*`, `lib/pipeline/*` | open |
| Y4 | `enumFactsAreSwitchesNotData` | Facts about an enum's variants are written as `switch` arms alternated with `\|\|` (275 such lines in 12 files: 105 in `claudart_command.dart`, 100 in `session_state.dart`, 27 in `failure_type.dart`), and 85 switches test status-like subjects, instead of each variant carrying its facts as constructor data on an enhanced enum (a data class the enum holds) and consumers reading the field | `claudart_command.dart`, `session_state.dart`, `failure_type.dart`, `agent_flow.dart` | open |
| Y5 | `folderLayoutLooseAndMixed` | 14 files sit loose in `lib/` (`paths`, `registry`, `config`, `git_utils`, `file_io`, `process_runner`, `md_io`, `pubspec_utils`, `ignore_rules`, `dependency_config`, `knowledge_templates`, `portability_gap`, `version`, the barrel), and `lib/commands/` holds files that are not commands (`failure_boundary`, `project_selector`, `scope_files`, `claudart_command`) while helpers of one command (doctor's) live in other folders | `lib/` layout | open |
| Y6 | `userTextWrittenInCommands` | Text a user reads is written inline in the commands: 410 `print` calls and 1086 string literals of 12 or more characters in `lib/commands/`, with no single place (a config file with accessors) that owns it, so the same intention is worded in several places | `lib/commands/*.dart` | open |
| Y7 | `integerConstantsStandInForAnEnum` | A menu whose choices were integer constants compared to a pick (`_SetupMenu` in `setup.dart`; the launch menus before D1), so a wrong constant compiled and was silently ignored, and the tests had to copy the constants because they were private. Closed: `SetupMenu` is a public enum owning its labels, one shared `chooseFrom` in `lib/ui/menu.dart` turns a pick into the choice (launch and setup both use it, and a pick naming no choice is a range error), and the copied constants in the tests are gone. The construct-choice detector now holds this count at zero | `setup.dart`, `menu.dart`, `choose_from_test.dart`, `construct_choice_test.dart` | closed |
| D14 | `titleMemberNamesAreOnlyText` | A test title written `'$Type.member'` references the type for real (`$Type` is the type's `toString()`, so a rename breaks it) but the member after the dot is plain text: renaming the member leaves the title naming something that is gone. 31 titles use `$Type`; 22 add a `.member`. Related: `$Type` is a `Type` interpolated, not a `String`; it is stable on the VM and for the compiled CLI, but not under obfuscation or dart2js minification and it carries type arguments (`List<int>`), so it is a test-title device, not a way to name types in `lib/`; and braces (`${Type}`) are forbidden by `unnecessary_brace_in_string_interps` for a plain identifier and needed only for an expression such as `${status.name}`. Closed for the member part in this step by a guard that fails when a titled member is not written in the type's file; the guard found no stale title and a seeded one trips it | `literal_ownership_topology_test.dart`, `make liveness` seed T8 | closed (guard); `Type` naming outside titles accepted with the reason above |

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
| M4 | `olderMutationSurvivors` | Mutation runs over the files this work touched found survivors in older, untouched lines, to be filed as one issue (not fixed inline, per the repo rule): `handoff_template` 33, `report` 40, `pipeline_executor` 37, `save` 26, `debug` 24, `rotate` 23, `kill` 21, `status` 17, `token_map` 10, `logger` 9, `workspace_config` 8, `teardown_utils` 7, `resume` 5, `sync_check` 3, and one each in `hook`, `failure_type` and `xml_tags`. `teardown` cannot be measured: it hangs the mutation tool | mutation runs, this document's progress notes | open, issue not yet filed | Also `process_runner.dart` `killProcessTree` (2026-10-30): the `process.kill` after the tree kill and the `kill -9` argument survive mutation; both are older lines. `paths.dart` (2026-10-30): 20 survivors in lines 53 and 100-151, none in the lines changed that day.


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
| R10 | `statusDisagreesWithHandoffContent` | Of 179 archived handoffs and checkpoints (measured with `make handoff-consistency`, which parses each with the real parser), 20 disagree with themselves: 16 hold a root cause and scope while the status still says the transfer is in progress, and 4 say it is complete while the root cause or scope is a placeholder (11%). The lifecycle scenarios now prove the commands themselves leave status and content agreeing after every command; the disagreements come from agents editing the handoff directly (S4) | `tool/refactor_audit/handoff_consistency.dart`, `lifecycle_test.dart` | open (commands proven consistent; direct edits remain) |
| R11 | `commandsLeaveNoOutcomeRecord` | `kill`, `teardown` and `suggest` never write an interaction record, so a warned `kill` and an unwarned one, a `teardown` the user confirmed from the wrong status, and a rejected `suggest` look the same, or are absent, in the logs. The step that makes `kill` illegal has no data on how the warning was answered. Found by claudart's own review, confirmed by grep | `kill.dart`, `teardown.dart`, `suggest.dart` (no `logInteraction`); `docs/briefs/claudart_review_2026-10-27.md` | open |
| K1 | `workspaceKnowsNoFeatures` | The workspace records no Feature variants: `workspace.json` holds owner, project and session only, and `skills.md` is keyed by branch, category and files, not by Feature variant. Owner's direction: when a Feature variant is updated, the workspace should know which features exist in it. Scope not yet confirmed (derived from the project's enums, or declared) | `workspace.json`, `skills.md` | open, awaiting the owner's scope |
| K2 | `handoffHasNoType` | One `handoffTemplate` function renders every handoff (`setup.dart:179`, `rotate.dart:191`); the handoff records no type. `flow` classifies an `AgentCategory` in its own run and logs it, but never writes it into the handoff | `handoff_template.dart:3`, `flow.dart:226` | open |
| K3 | `scopeIsOneShapeForEveryKindOfWork` | `suggest` writes the same Scope sub-sections (files, entry points, classes, must-not-touch) for a bug, a feature, a refactor and a spike | `suggest.dart:277-284` | open |
| K4 | `knowledgeNotKeyedByFeature` | Knowledge is generic files plus one file per project; no file is keyed by a Feature variant, and `suggest` is told to read every generic file listed for the workspace, not the ones relevant to the handoff's feature | `knowledge/` layout, `setup_template.dart:31-39` | open |
| K5 | `threeCategoryTaxonomies` | `AgentCategory` (feature, bug, refactor, research, setup, gui), `TeardownCategory` (the skills categories) and the owner's handoff types (bug, feat, refactor, spike, story) are separate lists with no mapping between them | `categorization.dart:148`, `teardown.dart:195-209` | open |
| K6 | `ticketMetadataNotModeled` | Nothing in claudart models the ticket a handoff comes from. The owner's direction: the type of work will arrive as metadata on a sprint-board ticket (zedup owns the board), through an event-driven ticket flow, so `suggest` and `flow` are given a type instead of classifying one. Not yet vetted by the owner | owner direction, 2026-10-26 | open, placeholder (H1 to H4) |
| K7 | `debugDispositionNotRecorded` | Nothing in the handoff records whether debug is pending, done, not applicable or skipped: `debug` runs on whatever status allows it, and `teardown` asks the user. A type of work such as a spike should declare debug not applicable, and a decision not to use debug should be written down, not inferred | owner direction, `teardown.dart:96-110` | partly closed (Q2): the disposition is a typed value recorded in the handoff and `debug` writes `done`; nothing writes `notApplicable` or `skipped` yet, and `teardown` does not read it (S10) |

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
| S12 | drivesState x processBound | existing |
| S13 | drivesState x processBound | existing |
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
| D16 | untouched x workspaceBound | existing |
| Y1 | untouched x pure; drivesState x pure; observesState x pure | existing |
| Y2 | drivesState x processBound; untouched x processBound; observesState x processBound | existing |
| Y3 | untouched x processBound; untouched x workspaceBound; drivesState x processBound | existing |
| Y4 | drivesState x workspaceBound; untouched x pure; drivesState x pure | existing |
| Y5 | — | new: CodeTree |
| Y6 | drivesState x processBound; untouched x processBound; observesState x processBound | existing |
| Y7 | drivesState x processBound | existing |
| D13 | drivesState x workspaceBound; observesState x workspaceBound; untouched x workspaceBound; untouched x pure; drivesState x processBound | existing |
| D14 | — | new: CodeTree |
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
| R11 | drivesState x processBound | existing |
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
| Q12 | `shapeTopologyAndBases` | Y1 | Q1 | the shape invariant I1 as an analyzer-based test with today's pairs as its ratchet; then each family of classes that shares properties gets an abstract base holding them (the `AgentResponse` variants, the `PipelineEvent` subclasses, the workspace config sections) with variants overriding getters or built by one factory |
| Q13 | `seamBundle` | Y2 | Q12 | invariant I2 (done 2026-10-30, ratchet 0) at today's count; one bundle type for the injected seams, passed down instead of nine loose parameters; each command takes it and the guards for the model seam and the funnel read it |
| Q14 | `oneSourcePerDatum` | Y3 | Q13 | invariant I3 with an owner table; git, project identity, workspace, credentials and settings are each reached through one module's accessors, and every other file calls them |
| Q15 | `enumFactsAsData` | Y4 | Q14 | invariant I4; `HandoffStatus`, `ClaudartCommand`, `FailureType` and `AgentFlow` carry their facts as enhanced-enum constructor fields (a data class per enum where the facts group), and the `\|\|` switches go; the relational `after` stays a function and the proofs P1 to P14 must still pass unchanged |
| Q16 | `folderLayout` | Y5 | Q14 | invariant I5; loose `lib/` files move into folders by concern, non-command files leave `lib/commands/`, a command's helpers sit beside it; moves are mechanical (imports only) and the whole suite and the topology docs must be unchanged apart from paths |
| Q17 | `userTextFromConfig` | Y6 | Q15 | invariant I6; the text a user reads moves to one config file with accessors, repeated wording is merged, and `D11` (repeated literals) falls with it |

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

- **Q2 `intendedBehaviorDecided`, first decisions: done, provisional.** The
  owner accepted the four recommendations on 2026-10-27 (recorded as
  provisional until the owner has seen them run). Built test-first:
  `HandoffStatus.nextStep` is the one text per status for what to do next, used by
  `status` and by the rejection message, so `suggest` from `debugComplete` is
  still rejected but now says "Next step: Verify with dart test, then claudart
  teardown to keep what was learned, or claudart rotate for the next issue"
  (partly closes S5: `save` still has its own switch). `kill` from `debugComplete`
  prints a warning that nothing is learned (`HandoffStatus.killWarning`), and every
  `kill` exit after the project is known now writes an interaction record
  named by `KillOutcome` (killed, killedWithWarning, cancelled, noInput,
  lockNotCleared, closeFailed, workspaceLocked), so the later step that makes
  `kill` illegal has data (partly closes R11: `teardown` and `suggest` still
  write none). A `kill` outside any project still writes nothing, which the
  workspace isolation test requires. The hook stays fail-open and the
  `readyForDebug --fixApplied` cell stays as `debug`'s start check, unchanged.
  Mutation: no survivor in a changed line in `session_state.dart`,
  `invalid_handoff_transition_exception.dart` or `kill.dart`; `status.dart` shows
  one mutant at the next-step print that the mutation tool reports as surviving
  but that the two variants I could reproduce by hand (a duplicated print, a
  shifted one) both fail the tests on, so it is recorded as unexplained, not
  fixed. Still to do for Q2: the typed KT-converged value, the debug
  disposition, `suggest` not applying `saveConfirmedReady` without a root cause
  (D9), and the `kill` rule's second step, which waits for Q11.

- **Q2, knowledge transfer value: done, provisional.** `KnowledgeTransfer`
  (`knowledge_transfer.dart`) is derived from a handoff's root cause and its files
  in play, never from the status line; `SessionState` now carries the scope and
  exposes `knowledgeTransfer`; each status states what it expects
  (`knowledgeTransferExpectation`, the owner's table) and `SessionState.findings`
  lists where status and content disagree (`HandoffFinding`). One correction
  to the provisional table, found by the new lifecycle check: after a blocked
  `debug` the status is `needsSuggest` but the root cause is still in the file, so
  `needsSuggest` expects nothing about the transfer (it was marked unconverged).
  Mutation: no survivor in a changed line (two prose mutants were fixed by pinning
  the message; an untestable spinner line was removed). Still to do for Q2: the
  debug disposition, and recording it in the handoff template.

- **Q2, debug disposition: done, provisional (the typed value and its record).**
  `DebugDisposition` (`debug_disposition.dart`: pending, done, notApplicable,
  skipped, with `wire` spellings and `isResolved`) is recorded in a new
  `## Debug Disposition` section of the handoff (`pending` in a new handoff, a
  placeholder in the blank one); `debug` writes `done` with `fixApplied`;
  `SessionState` exposes `recordedDebugDisposition` (null when none, never a
  guess) and `debugDisposition` (the status's answer when none is recorded);
  and a recorded disposition that contradicts the status (`done` only with a
  finished fix, a finished fix only with `done`) is a `HandoffFinding`. Handoffs
  that predate the section still read correctly. Mutation: no survivor in a
  changed line (two template separator lines were pinned by tests). Still open:
  nothing writes `notApplicable` or `skipped`, and `teardown` does not read the
  disposition, so S10 (a resolved-without-debug handoff cannot be torn down) is
  not closed; that is the next step, with the `HandoffStatus.after` table
  change written test-first.

- **Q2, the teardown table change (S10): done, provisional.** The first change
  to `HandoffStatus.after` itself, written test-first: `tornDown` is legal from
  the four statuses that expect a complete knowledge transfer (3 new legal cells,
  36 in all; shown in the README's diagram and `docs/design.md`'s extension
  table). `teardown` asks to record debug as skipped before it archives a handoff
  debug never finished. Two lifecycle scenarios drive the new cells; the third
  (`debugInProgress`, which no command rests in) is undriven, so the undriven
  ratchet rose from 14 to 15 once, with its reason in the test. Proofs P1 to P9
  and P14 hold and the 44 real moves still replay. In the same step the teardown
  pipeline became injectable and logged (S7, S12; 37 tests had been able to start
  the real model, and a guard now stops that). Mutation: the table file has no
  survivor in a changed line; `teardown.dart` still hangs the mutation tool at
  mutant 43 even with the model seam injected (so the hang is not the model), and
  stays unmeasured, covered by 38 teardown tests and the two scenarios.

- **Q6, D5 to D7: done.** D6 (`HOME` unset is a typed failure through a pure
  `workspacesRootFor`) and D7 (one saved token map per call, so no collision and
  tokens that persist) are closed; D5 is accepted with its reason. The step also
  found and closed S13 (a sensitive `setup` scanned the real filesystem) and added
  `make leak-check`, an instrument that runs the whole suite with HOME and the
  workspace root pointed at empty directories and fails if any test leaves a file;
  it passes and a seeded leaking test trips it. Mutation: no survivor in a changed
  line (one `abstractTexts` mutant was fixed with direct tests). Still open under
  Q6: D1, D2 (non-enum arms), D11 (174 repeated literals), D13 (typed values).

- **Q6, D1: done.** The three launch menus are enums that own their labels; no
  default arm remains in that switch. Mutation on `launch.dart` hangs the tool (it
  ran past twenty minutes and was stopped, file restored), so it is unmeasured;
  26 launch tests, including one per menu choice and one per label, cover it.
  Still open under Q6: D2 (non-enum arms), D11, D13.

- **Q6, D2: done.** The three parsers that turned an unknown name into a quiet
  default now return null and their callers say so (see D2 in the register); four
  string-subject wildcard arms are accepted with reasons. Mutation: no survivor in
  a changed line in `sync_check.dart`, `workspace_config.dart` or
  `preflight_cmd.dart`; `link.dart` hangs the tool past its cap, so its changed
  block (the unknown-role note) was checked by three hand-made mutations, all
  caught by a new test. Still open under Q6: D11 (174 repeated literals), D13
  (typed values), D16.

Why this order: Q1 first because every later step needs a tool that would
notice a regression. Q2 before any code because the real logs show behavior
the table does not describe (R2, R3), and only the owner can say which is
intended. Q3 before Q4 because a stream of transitions is only complete if one
writer publishes them. Q6 depends only on Q1 and can run beside Q3 to Q5.

### Sandboxed experiments and recommendations (2026-10-27)

Each experiment ran in a scratch copy or an in-memory sandbox and left the
working tree as it was. Recommendations are the assistant's, drawn from the
data; the decisions stay the owner's.

| Experiment | Result |
|---|---|
| Sensitive-logs sweep (`test/conformance/sensitive_logs_test.dart`): `suggest` and `debug` run against a sensitive project with a model that fails naming the project's identifiers, then every file under its logs read | clean after D12; the same run on a project that is not sensitive does contain the names, so the check can see them; forcing the logger back to plain makes both sensitive cases fail, so it would have caught the old leak |
| Cost of a log append at 0, 500 and 2000 preloaded lines (real files) | 220, 287 and 522 microseconds per append; a debug run appends about 11 times, so about 6 ms in the worst case: P1 is real but not worth fixing before the behavior work |
| Cost of one `git rev-parse` spawn | about 16 ms; the doubled spawn per command costs 16 ms |
| Candidate `kill` rule (only from `suggestInvestigating` and `needsSuggest`) replayed over the 44 real moves | would forbid 8 of the 9 real kills, all from `debugComplete`, the sessions ended with `kill` because `teardown` costs a model step |
| `readyForDebug --fixApplied` made illegal (earlier experiment) | 24 lifecycle runs that call `debug` fail |

Recommendations for the open decisions:

1. **`suggest` from `debugComplete`: reject, with a message saying what to
   run** (`save` then `teardown`, or `rotate` for the next issue). No data says
   anyone wants the new move (two attempts in two days), and allowing it adds a
   legal cell that needs its own scenario.
2. **Hook on an unreadable `workspace.json`: stay fail-open and logged.** The
   commands that spend model calls already stop; a hook that blocked edits on a
   corrupt config would lock the owner out of the file they need to fix.
3. **`kill` rule: adopt it, but in two steps.** First make `kill` from
   `debugComplete` print a warning that nothing will be learned; make it illegal
   only after the verified-closure `teardown` exists (H6, Q11). Today the rule
   alone would push the 8 sessions above toward the unsafe habit, because
   `teardown` is the expensive path.
4. **`readyForDebug --fixApplied`: keep it as `debug`'s start check now;
   decouple it when `debug` goes through the single writer (Q3).**
5. **Q7 moves to last.** Its measured costs (about 6 ms of log appends per
   `debug` run, 16 ms per extra git spawn) are real but small next to the
   state-machine work.

### Independent review by claudart (sandboxed `suggest`)

A real `claudart suggest` run in a throwaway workspace on a copy of this repo,
asked to review the logging and the open decisions (`CLAUDART_WORKSPACE` and the
project both under `/tmp`; the real workspace and registry were not touched).
Its full analysis is saved unedited in `docs/briefs/claudart_review_2026-10-27.md`.
The assistant checked each claim against the code and the logs:

| Claudart's point | The assistant's check | Outcome |
|---|---|---|
| All four recommendations are right; Q7 last is right | agrees with the experiments | confirmed independently |
| Recommendation 1 and 2 are already built in code (the `suggest` rejection, the hook's logged fail-open) | true; only the message text and the cap are open | noted |
| The "two attempts" behind recommendation 1 are not tied to a log record | wrong: `errors.jsonl` holds `suggest.invalidHandoffTransition` with count 2 (written by the failure boundary); it is not a transition because a thrown rejection is not one | corrected |
| The hook can flood the error log | no: `logError` deduplicates by fingerprint under a lock, so one line with a rising count; the cost is a lock and a file rewrite per edit, small | not a gap |
| `kill` from `debugComplete` is logged as an ordinary legal move, and no command records whether the warning was shown or overridden | true (grep: `kill`, `teardown`, `suggest` never call `logInteraction`) | new gap R11 |
| `teardown` confirmed from the wrong status is logged `rejected` with no `to`, so the real-log replay must say how rejected lines count | true | proof table row refined |
| "Fix verified" in `teardown` really means "fix written" | true (S11) | already recorded |
| Protection on read is not needed | agrees: protection is at write, and the sweep shows the files clean | confirmed |

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

### Audit run (2026-10-27)

Every instrument the repo has, run on the tree at `920fcd2` plus the proofs
section below. Nothing was skipped silently; the exceptions are named.

| Instrument | Result |
|---|---|
| `dart test`, random order | 3587 pass |
| `dart analyze` | 18, the baseline |
| `dart run custom_lint` | clean; it also flagged the first draft of the new proofs test (a loop over enum values inside one test), which was rewritten as one test per cell: the project's own rule caught new code |
| `make liveness` | 20 of 21 seeds caught; the miss is the plain `String == literal` comparison (U2), accepted with a reason |
| generated docs (`make topology`) | all current: the drift tests pass |
| `make handoff-consistency` on the real archive | 159 of 179 consistent; 4 status-ahead-of-content, 16 content-ahead-of-status, 0 disposition disagreements |
| `make spawn-census` | unchanged: 2 git spawns for `status`, `save`, `resume`, `preflight`, `scan`, `report`; 5 for `doctor`; 1 for `hook` and for `status --project` |
| `make consumer-check` | fails to compile zedup against this checkout (X8, unchanged, zedup is paused) |
| `make check-coverage` | passes: 88.2% overall against an 84.0% floor; `lib/session` 97.0%, `lib/logging` 95.8%, `lib/templates` 99.0%, `lib/workspace` 95.2%, `lib/codegen` 93.3%, `lib/errors` 100% |
| `make test-only-census` | 12 symbols used only by tests, unchanged (advisory) |
| mutation testing | run per slice on every `lib/` file this refactor touched, none with a survivor in a changed line, except `teardown.dart` (hangs the tool, upstream issue #77) and `flow.dart` (timed out earlier). A whole-branch `make mutation-test-changed` was started and stopped after five files: it re-measures older, untouched code at about three minutes a file (about three hours), and those survivors are already recorded as M4 |
| the proofs (P1 to P9) | 113 cases pass; two deliberate breaks of the table were caught (see the proofs section) |

### Construct selection proof: which Dart construct fits a case (2026-10-29)

The owner's request: a proof that, for a given case, says whether it needs a
switch, an if, a guard, an extension, a factory, an abstract class, a class, an
enum and so on, so the best fit is used when passing data and extending things.
It is `test/helpers/construct_choice.dart` (the decision table) and
`test/topology/construct_choice_test.dart` (the proof and the detectors).

A case is ten facts: whether the alternatives are a closed set, whether they
carry different data, how many places branch on them (none, one, many), whether
each yields a plain value, whether types share properties, whether the instance
is chosen by input, whether the type can be edited, how many outcomes there are
(one, two, three or more), whether the failing branch ends the function, and
whether three or more related values travel together. The facts come from small
finite domains, so the whole space is 2^7 x 3 x 3 x 2 = 2304 cases.

The table is an ordered list of thirteen named rules; the first that applies
decides:

| Rule | When | Construct |
|---|---|---|
| `guardForPrecondition` | the failing branch ends the function and there are two or fewer outcomes | guard clause |
| `bundleForRelatedParameters` | three or more related values are passed together | one class or record |
| `sealedForDifferingData` | a closed set whose variants carry different data | sealed hierarchy |
| `enumFieldForRepeatedFacts` | a closed set, no per-variant data, branched on in many places, each yielding a plain value | enhanced enum constructor field |
| `sealedForRepeatedBehavior` | the same, but the result is behavior | sealed hierarchy, variants override the method |
| `switchForOneMapping` | a closed set, no data, one place decides | one switch |
| `enumForClosedSetWithoutData` | a closed set, no data, nothing branches on it yet | plain enum |
| `baseForSharedProperties` | two or more types hold the same properties | abstract base class |
| `factoryForChoiceByInput` | which instance gets built depends on an input | factory constructor |
| `extensionForUneditableType` | behavior must be added from outside | extension method |
| `ternaryForTwoValues` | two outcomes that are plain values | conditional expression |
| `ifElseForTwoBranches` | two real branches | if and else |
| `switchForManyBranches` | three or more outcomes | switch |
| `nothingToDecide` | one outcome | no branching |

What the proof establishes, over every one of the 2304 cases:

- **Totality:** every case is decided by some rule (a case no rule decides throws,
  and 18 tests, one per setting of the three graded facts, check all 128 yes-or-no
  combinations of each).
- **No dead rule, no dead construct:** every rule is the deciding rule for some
  case, and every construct is chosen for some case.
- **The best-practice properties:** a precondition with two or fewer outcomes is
  a guard; three or more related values are a bundle unless a guard applies; a
  closed set whose variants carry different data is sealed; facts repeated at
  many sites are enum fields and never another switch; behavior that differs per
  variant at many places is overridden on the variants; a switch over a closed
  set appears only where one place maps the variants; and a repeated decision
  never falls back from a field to a switch.
- **Named cases:** twelve real situations in this repo are each pinned to the
  construct they call for (the status next-step text is an enum field, the agent
  response variants are sealed, "stop when the project is not registered" is a
  guard, nine seams are a bundle, a menu of integer constants is an enum, and so
  on).

The proof found a hole while it was being written: the first table had no rule
for behavior (not a plain value) repeated at many places, and the switch property
failed on it; `sealedForRepeatedBehavior` was added. Two breaks show it can fail:
disabling the enum-field rule fails the proof, and adding an enum with two getter
switches fails the detector.

The detectors turn real code into facts so the same table judges it. Three run
today, each held at a floor that may only go down:

| Detector | Case found | Construct the table gives | Count now |
|---|---|---|---|
| `enumsWithFactSwitches` | an enum stating two or more facts as getters that switch on `this` (Y4) | enhanced enum field | 13 (`HandoffStatus` 7, `ClaudartCommand` 6, `FailureType` 4, `DesignSurface` 4, `StepRole` 3, `FaultClass` 3, `CategorizeTag` 3, and six more with 2) |
| `intConstantNamespaces` | a class of integer constants standing in for an enum (Y7) | plain enum | 0 (was 1) |
| `seamHeavyFunctions` | a function with three or more seam parameters (Y2) | bundle type | 9 (`runRotate` 7, `runKill` 6, `runLauncher` 5, `runDebug` 5, `runDoctor` 4, `runChatShell` 4, `runArchives` 4, `runStatus` 3, and one more) |

Not yet detected, said plainly: shared properties between classes (I1, needs an
analyzer pass, not a regex), single source per datum (I3), layout (I5), inline
text (I6), boolean flag parameters that select behavior, and an if-else chain on
one variable that should be a switch. Each is a fact the table already has a rule
for; what is missing is the detector.

### Proofs against missed consolidation (defined 2026-10-28, owner's direction)

The owner's finding: the families so far classified code by what it does (state
role, reach), never by what it holds, so structural duplication went unseen and
each gap was fixed as a local patch. Consolidation means the shared shape is
written once, as an abstract (base) class, an enhanced enum's constructor data, a
bundle type or a single accessor, and the callers extend or read it; variants
differ only by overriding getters or by a factory that switches once on the enum.

Definitions. A *shape* sigma(x) of a declaration x is the finite set of
(name, type) pairs it holds (a class's fields, a function's parameters, an
enum's per-variant facts). For two declarations the overlap is
o(x, y) = abs(sigma(x) cap sigma(y)) / min(abs(sigma(x)), abs(sigma(y))). A pair
is *consolidatable* when abs(sigma(x) cap sigma(y)) >= k and o >= theta. Let
Inherits be the pairs related by `extends`, `implements`, `with`, or a shared
typedef, and Ledger the pairs recorded with a reason that their variance is real.

| Id | Invariant | Decided by | Status |
|---|---|---|---|
| I1 | Shape: every consolidatable pair of classes is in Inherits (directly, or through a common base) or in the Ledger | an analyzer pass over `lib/` computing sigma and Inherits; the test fails naming each pair outside both sets | built (analyzer; ratchet 0) |
| I2 | Seams: a function that declares three or more of the seam parameters (`io`, `runner`, `exitFn`, `confirmFn`, `promptFn`, `pickFn`, `projectRootOverride`, `mode`, `executor`) takes one bundle type instead | signature scan; a ratchet to zero | measured (Y2); not built |
| I3 | One source: for each external datum d (the environment, a process, git, the credentials and settings files, `registry.json`, `workspace.json`, `config.json`, `handoff.md`) there is one owner module M(d), and no other file in `lib/` or `bin/` contains an access pattern for d | pattern scan against an owner table, like the log-name guard | measured (Y3); not built |
| I4 | Enum data: for each enum E, the number of `\|\|`-alternation lines in switches over E is at most the number in its one relational function (for the state machine, `after`); facts are constructor fields | switch scan per enum; a ratchet to the relational floor | measured (Y4); not built |
| I5 | Layout: `lib/` holds only the barrel at its root; a folder is one concern; `lib/commands/` holds only files named for a `ClaudartCommand` | file-tree scan | measured (Y5); not built |
| I6 | Text: user-facing literals of 12 or more characters in `lib/commands/` are read from one text owner, not written inline | literal scan; a ratchet to zero, with the owner a config file plus accessors | measured (Y6); not built |

Soundness, said plainly. I1 to I6 are decided on the finite set of declarations,
so each holds or fails exactly; what they cannot prove is that k and theta are the
right thresholds, only that no pair above them is missed. A pair below them, or a
consolidation of behavior rather than shape, is not covered; the Ledger is the
place to say why a pair that looks alike is not.

Order of work for these, test-first: build the measurement and its ratchet at
today's number, then consolidate until the number reaches its floor, then lower
the ratchet. None starts before the owner has read this section.

### Proofs of the topology: what is proved, how, and what is not

The handoff state machine is the triple (S, E, delta): S = `HandoffStatus` (8),
E = `HandoffEvent` (13), and delta : S x E -> S u {rejected}, the partial function
`HandoffStatus.after`. Let L = {(s, e) : delta(s, e) is a status} be the legal
cells and G the directed graph on S with an edge s -> delta(s, e) for each
(s, e) in L. Every set is finite, so a property of delta is decided by checking
all 104 cells, or by a search over G: that is a proof, not a sample. Properties
that depend on running commands are verified over a finite set of scenarios and
are labelled so. `test/topology/transition_proofs_test.dart` holds the executable
form; the expected values are independent literals.

| Id | Statement | How it is decided | Status |
|---|---|---|---|
| P1 | Totality: for every (s, e), delta(s, e) is decided, never undefined | the Dart switch is exhaustive (a missing cell fails to compile) and 104 cell tests | proved |
| P2 | Determinism: delta is single-valued | a Dart switch returns one value; each cell is evaluated twice and must agree | proved |
| P3 | Size: abs(S) = 8, abs(E) = 13, abs(L) = 36 (33 before the teardown change) | pinned literals; a table change fails until it is made on purpose | proved |
| P4 | Isolation: no legal move enters or leaves `unknown` | search over G | proved |
| P5 | Reachability: every live status (S without `unknown`) is reachable from `noHandoff` | breadth-first search over G | proved |
| P6 | No trap: from every live status `noHandoff` is reachable | search over G | proved |
| P7 | The live statuses form one strongly connected component | follows from P5 and P6 (any two meet through `noHandoff`); also checked directly | proved |
| P8 | Self-loops exist exactly at `suggestInvestigating`, `readyForDebug` and `debugInProgress` | edge enumeration against a literal | proved |
| P9 | Real-use replay: for each of the 44 real moves m, delta(m.from, m.event) = m.to | the fixture `test/fixtures/real_transitions.jsonl` (enum names only) | proved for these 44 |
| P10 | Status follows content: after every command of every lifecycle scenario, `findings` is empty | 13 scenarios x 6 environments | verified over the scenario set, not proved for all handoffs; 20 of 179 real saved handoffs disagree (R10), from direct edits |
| P11 | Every legal cell is driven by a scenario | `transition_matrix_test.dart` ratchet | not met: 15 of 36 undriven |
| P12 | Termination: if the relation R(e) = events a listener may return after e is acyclic, a listener chain has at most abs(E) = 13 hops | topological order of E | not provable yet: no listeners exist |
| P13 | Safety: for every legal (s, e) and every e' in R(e), delta(delta(s, e), e') is legal | check over L x R | not provable yet: no listeners |
| P14 | The teardown rule: delta(s, tornDown) is legal exactly when the status expects a converged knowledge transfer | one test per status against `knowledgeTransferExpectation` | proved for the table; the other half of the rule, that `teardown` applies the move only once the disposition is resolved, is a command rule verified by the teardown tests and two lifecycle scenarios, not a property of delta |

How a break shows. Two deliberate breaks of the table were applied in a scratch
state and reverted:

- `kill` made illegal from `debugComplete` (and `reminderSaved` with it, they
  share an arm): P3 fails (33 becomes 31) and P9 fails (8 of the 44 real moves
  become illegal).
- `setup` made to land in `unknown`: P4, P5, P6 and P7 fail.

What is not proved, said plainly: P12 and P13 (no listeners yet), P14 (not
built), anything a command does besides the move, and the absence of races once
the stream is asynchronous (the drain, order and isolation checks of stage 3
cover that and are not built).

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
| Real-log replay | the real `transitions.jsonl` moves (44 on this machine) replay through the new table and every one that was legal still is, so no real session becomes illegal; a line logged `rejected` is counted separately and stays rejected (a rejected move has no `to`), so it cannot silently become an applied one |
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
| T8 | `titleNamesMissingMember` | literal ownership guard | a title `$Type.member` where the member is gone | caught |
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
