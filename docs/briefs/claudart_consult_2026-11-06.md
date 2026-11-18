# Brief for claudart: where the refactor stands (2026-11-06)

Read this, then the files listed at the end. The code was written by hand by the
assistant, not produced by claudart, so check the implementation against what
is claimed here before you trust it. Nothing in this brief is to be pushed.

## What this work is

A refactor so claudart's state machine, logs, tests and proofs enforce the
architecture, and code added by an agent or by claudart cannot fail silently.
`docs/methodical_refactor.md` is the record: a gap register (each gap has an id
and a family), a proposed order (Q1 to Q17), proofs, and what is open.
`CLAUDE.md` and `PLAN.md` are the law; `docs/design.md` is the state machine.

## Where it stands

Branch `claudart/enum-matrix-architecture`, all local. 4216 tests pass in random
order, `custom_lint` is clean, the analyzer shows 13 older infos. `tool/gate.sh`
(`make gate`) runs everything and commits only if it passes.

| Done | What |
|---|---|
| Q12 | `class_shapes.dart`: classes holding the same fields share one base; ratchet 0 |
| Q13 | `CommandSeams`: the injected io, exit, confirm, pick, clock of every command in one value |
| Q14 | one source per datum: environment, home, processes, git, the project lookup (`lookupProject`) |
| Q15 | 13 enums state their facts as constructor data, not switches |
| Q16 | folder layout enforced by `layout_test.dart`; `lib/config`, `lib/io`, `lib/project`, `lib/commands/support` |
| Q17 | every printed sentence in `lib/commands` reads from `text/user_text.json` (generated `UserText`) |
| Q3 | `HandoffStore` is the one writer of `handoff.md` (`apply`, `rewrite`, `replace`) |
| Q4 core | `HandoffTransitionBus`: inline records, ordered reactions, drain, isolation; `listenersFor` exhaustive over events; reactions bound to the table |
| Q5 | `runRecorded` wraps the one dispatch: every command run leaves one row (`ok` or `failed`, with duration); `exitProcess` is the one exit; every log row names its `schema` |
| Q11 slice 1 | `debug` runs an optional `verificationCommand`; `ClosureEvidence` and its five-row evidence matrix (five scenarios, four evidence values: two scenarios end as `none`); `status` shows the closure |
| Spec mechanisms | `SpecObligation` (each spec obligation has a consulting symbol and named checks), a test-only-symbol ratchet, guards against real waits and process-global state in tests |
| Visibility | `make diagram` draws each recorded run as a Mermaid sequence diagram from the logs |

## What was found while doing it (all in the gap register)

- **T1 to T4, the spec against the tests.** The Q4 proofs passed over a table no
  runtime code read. Four causes: a proof of a model is not a proof of the
  system; the spec obligations were not traced to tests; the census that would
  have caught it was advisory; spec sentences admitted a conforming build that
  missed their words. Mechanisms for the first three are built.
- **R12.** Commands that log their own interaction also get the boundary's row.
- **R13.** A handled exit (`status` outside a project) logs that it failed, not why.
- **R14.** `rotate` archives before its gate runs. A failing gate leaves the
  archive and the handoff unchanged, so every retry archives again (checked:
  archive index 1 entry, then 2; `gates.md` counts files, not index entries).
- **R15.** Neither gate (`debug`'s `verificationCommand`, `rotate`'s
  `afterFixCommand`) logs the command's exit code or output.
- **The gate comparison** (`docs/topology/gates.md`, generated from real runs):
  the two gates ask different questions, sit at different points of the state
  machine, and a failure does different things to the state. They share one
  mechanism: a shell command, exit 0 passes, the same `sh -c` constants.

## What the owner has not decided

1. Should the two gates keep two config keys and two positions, with only the
   runner consolidated (one injectable function returning exit code and output
   tail, logging both)?
2. R14: archive only after the rotate gate passes, or accept the duplicate?
3. A headless `teardown` from `debugComplete` whose disposition is `done` (fix
   applied and analyzed, no verification): archive as today, or save a reminder
   because only verified evidence should update the workspace?

## What to do

Review, do not implement. Check each claim above against the code and the
generated docs, and say where it is wrong. Then give a recommendation, with the
reason, for each of the three decisions, and say what data would change it.
Say what the test-trace slice should record (each test's input, expected value
and actual value, merged into the run diagram) so a test's own integrity can be
checked, and whether the existing `SpecObligation` enum is the place to anchor
it.

## What must not be decided

The ticket flow, the Workspace Feature and the handoff type list (K1 to K7, H1
to H4, Q10) wait on the owner. Do not change `after`, the transition table, or
any `lib/` file.

## Read, in this order

`docs/methodical_refactor.md` (the status table and the gap register, T1 to T4
and R12 to R15), `docs/topology/gates.md`, `lib/commands/debug.dart`,
`lib/commands/rotate.dart`, `lib/commands/teardown.dart`,
`lib/session/closure_evidence.dart`, `lib/session/handoff_store.dart`,
`lib/commands/support/interaction_boundary.dart`, `docs/design.md`.
