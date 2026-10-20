# Methodical refactor

How a refactor is run when every step must be proven and nothing may be assumed.
This document is the feature's record: the stage sequence, the gap register, and
what each stage proved. It is written as the work happens, so it shows how the
work was actually done.

The approved plan is the source of the stage order (Phases 0 to 6). The
reasoning behind a stage is in `docs/session_log.md`; the roadmap entry is in
`PLAN.md`.

## Stage sequence

| Stage | Question it answers | Output | Proof type |
|---|---|---|---|
| 0 Tools prove they can see | Do the lints, tests, mutation and guards catch what they claim? | Tool-liveness matrix, call census | Seeded-defect table; counted reads |
| 1 Exhaust dependencies | What depends on what? | Signature per symbol, family enum, `docs/topology/families.md` | Every symbol in exactly one family |
| 2 Use-case matrix | What should happen in every state, per trigger? | Cells of status x event x trigger x link x sensitivity x dartrix | Expected derived independently, compared with the log |
| 3 Listener design | What reacts to a state change, and does it end? | Typed stream, per-cell switch | Closure graph has no cycle |
| 4 Close gaps | Which gaps are real, in what order? | One failing test, then one fix, per gap | Gates and mutation per item |
| 5 Cross-package truth | Where do claudart, dartrix, zedup meet? | One portal document | Generated from code |
| 6 Verify end to end | Does the whole still agree? | Re-run of stages 2 and conformance | Expected equals actual |

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
| L6 | `wildcardArmUndetected` | A wildcard arm in an enum switch is caught by no tool, so D2 can return unnoticed | stage 0.2 seed L6 | open |
| L7 | `bareStringComparisonUndetected` | A bare string compared with `==` is caught by no tool; `bare_string_for_enum` sees only switch dispatch | stage 0.2 seed L7 | open |
| L8 | `duplicateLiteralCheckAdvisory` | The duplicate-literal check is advisory: it prints and exits 0 | stage 0.2 seed D1 | open |
| L9 | `newLogFileNameUndetected` | A new log file name written as a literal is not caught, because the ownership guard knows only the names `LogFile` already holds | stage 0.2 seed T6 | open |

### Measured by the call census (stage 0.3)

| Id | Name | Gap | Evidence | Status |
|---|---|---|---|---|
| B2 | `killReadsRegistryTwice` | Confirmed: `kill` reads the registry twice (load, then the re-read inside `save`) | `docs/topology/call_census.md`, kill rows | open |
| P1 | `logAppendReadsWholeLog` | Every log append also reads the whole log to count lines for trimming: 10 appends in `suggest` cost 10 reads, up to 2000 lines each for `steps.jsonl` | census, `suggest` row; `logger.dart:400` | open |
| C1 | `censusCoversLifecycleOnly` | The census covers only the lifecycle scenarios (setup, suggest, debug, teardown, kill, rotate); save, status, resume, link, hook and the other commands are not measured yet | census scope | open |
| B1 | `gitSpawnedTwicePerCommand` | Confirmed with real processes: every command spawns `git rev-parse --show-toplevel --abbrev-ref HEAD` twice where once is enough (`status`, `save`, `resume`, `preflight`, `scan`); `doctor` spawns five (three `rev-parse`, `config user.name`, `config user.email`); `status --project` spawns one. The second spawn's call site is not yet attributed | sandbox run, below | open |
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


## Stage records

Each entry states the pass condition first, then the observed result.

### Stage 0.2 - tool liveness

Pass condition: for every tool and every defect shape it claims to catch, a
seeded defect in a scratch copy of the repo is reported. A defect it does not
report is a finding. The working tree is never seeded; the harness is
`tool/refactor_audit/liveness.sh` (`make liveness`) and copies the repo first.

Observed (18 seeds): 15 caught, 3 missed. The 18th seed (T7) is the call
census doc drifting, added when the script moved into `tool/`.

| Seed | Tool | Defect | Result |
|---|---|---|---|
| A1 | analyzer | type error | caught |
| A2 | analyzer | unused import | caught |
| L1 | custom_lint `bare_string_for_enum` | string switch with actions | caught |
| L2 | custom_lint `enum_values_loop_in_single_test` | enum `values` loop in one test | caught |
| L3 | custom_lint `ungrouped_identical_switch_cases` | identical arms | caught |
| L4 | custom_lint `unconditional_confirm_requires_prompt_fn` | `confirmFn` true, no `promptFn` | caught |
| L5 | analyzer `missing_enum_constant_in_switch` | enum switch missing a variant | caught |
| L6 | any | wildcard arm on an enum switch | **missed** |
| L7 | any | bare string compared with `==` | **missed** |
| D1 | `check_duplicate_literals` | same-file duplicate literal | caught (advisory, exit 0) |
| T1 | literal ownership guard | log file name literal in `lib/` | caught |
| T2 | literal ownership guard | test title naming a type as text | caught |
| T3 | handoff topology test | generated doc drift | caught |
| T4 | model metadata guard | model id literal in `lib/` | caught |
| T5 | environment topology test | generated doc drift | caught |
| T7 | call census test | generated doc drift | caught |
| T6 | literal ownership guard | log name literal not yet in `LogFile` | **missed** |
| R1 | random-order suite | order-dependent test (passes in declared order) | caught |

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
B2 and found P1. Both are recorded above, not yet fixed.

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
   it publishes each `HandoffTransition` on a sync broadcast
   `Stream<HandoffTransition>`, the way `PipelineExecutor.events` already does.
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
produced by any command.

Decisions that are yours, not derivable from the data: which sequences should
start automatically after which state (for example, after `fixApplied` run
analyze and the tests; after `debugBlocked` open the suggest step), and whether
a listener may ever be asynchronous (the stream is synchronous today).
