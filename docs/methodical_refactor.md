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

| Id | Gap | Evidence | Status |
|---|---|---|---|
| S1 | No status stream. The only stream is the pipeline's, with one subscriber | `logger.dart:203`; `pipeline_executor.dart:85` | open |
| S2 | Status written by direct string writes, not one writer | `debug.dart:67-70,182,335`; `save.dart:74`; `suggest.dart:125,294` | open |
| S3 | `rotate` and `kill` write the blank handoff outside `applyHandoffEvent` | `rotate.dart:181,200`; `kill.dart` | open |
| S4 | Agents edit `handoff.md` directly, bypassing the table | agent prompts, `docs/topology/handoff_status.md` | open |
| S5 | Four per-status switches re-derive behavior | `launch.dart:238`; `status.dart:118`; `render.dart:38`; `save.dart:190` | open |
| S6 | Setup, rotate, teardown, kill log a missing move as rejected and continue | `logger.dart:143` | open |
| S7 | Teardown pipeline has no log subscriber; subscriptions are dropped | `teardown.dart:144`; suggest/debug/flow | open |
| S8 | Pipeline FSM exists only as a comment | `pipeline_event.dart:3-24` | open |
| S9 | `LogFile.performance` has no writer | `logger.dart:326` | open |

### Exits that leave no record

`save.dart:62,73`; `teardown.dart:75,138`; `kill.dart:103,114,126`;
`suggest.dart:101,231`; `setup.dart:100,104,164`; `rotate.dart:96,104,132`;
`launch.dart:49,80,137`; `logger.dart:229`. A save from a status with no save
move writes a checkpoint with no transition and no log. Status: open (E1).

### Defaults and silent fallbacks

| Id | Gap | Evidence | Status |
|---|---|---|---|
| D1 | `default:` arm | `launch.dart:158` | open |
| D2 | Wildcard arms | `session_state.dart:29`; `failure_type.dart:82`; `claudart_command.dart:168,270`; `sync_check.dart:16,139`; `workspace_config.dart:41,61`; `chat_shell.dart:50`; `config.dart:80` | open |
| D3 | Corrupt registry reads as empty | `registry.dart:103` | open |
| D4 | Unreadable `workspace.json` makes `owner.strict` false | `suggest.dart:59`; `debug.dart:111`; `flow.dart:67`; `hook.dart:157` | open |
| D5 | Missing file reads as an empty string | `file_io.dart:41` | open |
| D6 | `HOME` assumed set | `paths.dart:75,79` | open |
| D7 | Token map updated but not persisted in setup and save | `setup.dart:191`; `save.dart:136` | open |
| D8 | Swallowed errors | `token_map.dart:91`; `link.dart:690`; `session_ops.dart:161` | open |

### Binding and source of truth

| Id | Gap | Evidence | Status |
|---|---|---|---|
| B1 | Git and registry re-resolved per command, 2 to 3 times with `--project` or debug | `bin/claudart.dart:155,175`; `failure_boundary.dart:49` | open, measure first |
| B2 | Registry re-parsed inside `save` | `registry.dart:128` | open, measure first |
| B3 | Two parsers for `config.json` | `config.dart:105`; `rotate.dart:212` | open |
| B4 | Project name and sensitivity held in more than one file with no agreement check | `registry.dart`; `workspace_config.dart` | open |
| B5 | `unlink` leaves registry entry, generated files, `.gitignore` lines, hooks path | `unlink.dart:27-41` | open, decide from data |
| B6 | `scan`, `report`, `map`, `doctor` ignore `--project` | `claudart_command.dart:179-208` | open |
| B7 | Knowledge dir assumed under the workspaces root | `link.dart:247`; templates | open |

### Cross-package

| Id | Gap | Evidence | Status |
|---|---|---|---|
| X1 | The type is `MatrixCell`; earlier notes named a type that does not exist | dartrix `matrix.dart:25` | closed (naming corrected here) |
| X2 | dartrix `cover` and `gaps` are runtime, not compile-time | dartrix `matrix.dart:62-79` | open |
| X3 | PARADIGMS promises a posture function and a lint package that do not exist | dartrix `PARADIGMS.md:20-42,184` | open (dartrix finding) |
| X4 | `HandoffStatusType` is a hand-kept mirror; `PipelineComponent` unused as an axis | `test/matrix/` | open |
| X5 | claudart has no shoelace snapshot producer | zedup `launcher.dart:50` | open |
| X6 | Contradictions between the three PLAN files; claudart PLAN Phase 16 evidence stale | see stage 5 | open |

### Tools that cannot see (found by stage 0.2)

| Id | Gap | Evidence | Status |
|---|---|---|---|
| L6 | A wildcard arm in an enum switch is caught by no tool, so D2 can return unnoticed | stage 0.2 seed L6 | open |
| L7 | A bare string compared with `==` is caught by no tool; `bare_string_for_enum` sees only switch dispatch | stage 0.2 seed L7 | open |
| L8 | The duplicate-literal check is advisory: it prints and exits 0 | stage 0.2 seed D1 | open |
| L9 | A new log file name written as a literal is not caught, because the ownership guard knows only the names `LogFile` already holds | stage 0.2 seed T6 | open |

### Measured by the call census (stage 0.3)

| Id | Gap | Evidence | Status |
|---|---|---|---|
| B2 | Confirmed: `kill` reads the registry twice (load, then the re-read inside `save`) | `docs/topology/call_census.md`, kill rows | open |
| P1 | Every log append also reads the whole log to count lines for trimming: 10 appends in `suggest` cost 10 reads, up to 2000 lines each for `steps.jsonl` | census, `suggest` row; `logger.dart:400` | open |
| C1 | The census covers only the lifecycle scenarios (setup, suggest, debug, teardown, kill, rotate); save, status, resume, link, hook and the other commands are not measured yet | census scope | open |
| B1 | Confirmed with real processes: every command spawns `git rev-parse --show-toplevel --abbrev-ref HEAD` twice where once is enough (`status`, `save`, `resume`, `preflight`, `scan`); `doctor` spawns five (three `rev-parse`, `config user.name`, `config user.email`); `status --project` spawns one. The second spawn's call site is not yet attributed | sandbox run, below | open |
| C2 | The census sees the FileIO seam only; git and `claude` process spawns need a separate measurement | census scope | open |

### Measured by the families (stage 1)

| Id | Finding | Evidence | Status |
|---|---|---|---|
| F1 | Exactly seven files drive handoff state, all processBound: `setup`, `suggest`, `debug`, `save`, `kill`, `rotate`, `teardown`. Each emits events itself; no single writer. This is the family the Phase 3 listener replaces. | `docs/topology/families.md`, `drivesState x processBound` | open |
| F2 | Four files observe state while processBound (`launch`, `status`, `workspaces`, `knowledge_templates`) and three are workspaceBound (`hook`, `session_ops`, `sync_check`): the readers that re-derive behavior per status | families doc | open |
| F3 | 24 files reach processes or the terminal and never touch state, among them `flow`, `resume`, `doctor`, `link`, `unlink`: commands that change the session's world with no state record | families doc, `untouched x processBound` | open, review per command |
| F4 | The classifier matches a name where it is only declared, so a portal's owner (`paths`, `registry`, `config`) sits beside its users | `topology_family.dart` header | accepted: owners are named in the doc |

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
