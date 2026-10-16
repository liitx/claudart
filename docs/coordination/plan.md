# Coordination plan — 2026-10-12

Goal: logical flows, honest tests, one layered architecture, claudart/dartrix/zedup aligned.
Rule: no code edits until the owner agrees this plan. Ledger IDs refer to `ledger.md`.

## Target shape (what "done" looks like)

1. **Typed transition function.** `HandoffStatus` + a `HandoffEvent` enum + `HandoffStatus transition(HandoffStatus, HandoffEvent)` (exhaustive switch, grouped arms). Every command writes status through it; `updateStatus(String)` goes away. (A1-A5)
2. **State machine as a stream.** `Stream<HandoffTransition>` (from, event, to, at) emitted on every transition; logging and tests subscribe to the same stream. (G)
3. **Mocks drive typed data.** `MockClaudeRunner` takes a scripted `List<PipelineEvent>`/responses keyed by step id (no substring match, throws on unscripted call). Tests assert `HandoffStatus` and `PipelineEvent` values, never `contains('text')`. (B1-B5)
4. **Exhaustive status matrix.** A test loops (in `group`, one `test` per variant) over `HandoffStatus.values`; `assertNoGaps` fails when any variant is untouched; delete the hand-copied mirror (B1, B3).
5. **Layers.** pipeline engine emits events only (no stdout, no menus); UI/commands render them. Data/logging layers do not import pipeline. (C)

## Slices, in dependency order

| Slice | Content | Needs | Repo | Session owner |
|---|---|---|---|---|
| 0 | Decide on `feat/mutation-runner-streams` (push + PR) | owner | claudart | runner session (done, awaiting owner) |
| 1 | Typed `transition()` + `HandoffEvent`; route all status writes through it; remove string compares (A1-A6) | 0 not required | claudart | session "fsm-transition" |
| 2 | `HandoffTransition` stream + structured logging of transitions and silent decisions (G) | 1 | claudart | "fsm-stream-log" |
| 3 | Test honesty: scripted mock, exhaustive status matrix, typed asserts for worst 10 (B1-B5), mutation run per touched file | 1, 2 | claudart | "test-honesty" |
| 4 | Pipeline executor stops printing/menus; typed events for approve/refine/exit/abort (C, G) | 2 | claudart | "executor-events" |
| 5 | Export `errors/` and `codegen/` from claudart; tag a release/pin a `ref` | 1-4 | claudart | "public-surface" |
| 6 | zedup migration: bump claudart pin, delete duplicate `FaultClass`, move exceptions into taxonomy, replace its runner with claudart's (removes hardcoded skip-permissions, adds timeout/provider check/typed errors), ArtifactEnum for generators, gate recompile (D1-D5) | 5 | zedup | "zedup-migration" |
| 7 | zedup tests on streams (coordinators, poller) using the typed-event pattern (B6, B7) | 6 | zedup | "zedup-tests" |
| 8 | dartrix: decide fate of unbuilt promises (posture function, lint rules, DartrixConfig), type snapshot status, fix stale docs, pin refs (B8, D6, D7, E) | parallel to 1-4 | dartrix | "dartrix-align" |
| 9 | Dead code and census gap (F), #75/#76/#82/#83/#85/#81/#56 | 3 | claudart | "debt" |
| 10 | Naming pass (H), done last so renames do not collide with slices above | 1-9 | all | "naming" |
| 11 | #87 routing/benchmark | 6 | claudart, zedup | later |

## Process

- Each sub-session: `claudart setup` -> suggest KT -> save -> debug -> test -> save; at the end it writes a one-paragraph hand-back into the coordinator handoff's "Debug Progress" and the coordinator updates `ledger.md` statuses.
- Per slice gate: `dart analyze`, `custom_lint`, full `dart test`, duplicate-literal check, `make mutation-test-changed` for touched lib/ files, bare-string and grouped-arm self-check, independent Opus review on anything non-trivial.
- Evidence before ledger: audit claims are `[A]` until re-checked against code.
- Never push or merge without owner confirmation; verify liitx identity before commits; no attribution lines.

## Decisions needed from the owner (consensus)

1. Slice 1 first (typed transition function) - recommended: it is the root of A and B.
2. Should the slice-1 design change `design.md` (to match reality) or the code (to match `design.md`)? Recommended: code to match design, since design.md is the formal spec.
3. dartrix: build the promised posture function and lint rules, or trim the docs to what exists?
4. zedup runner: replace with claudart's (removes the hardcoded `--dangerously-skip-permissions`)? Recommended yes.
5. Push `feat/mutation-runner-streams` now?
