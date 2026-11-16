# Candidacy progress log (agents: read this first)

Append-only, newest last. One entry per step: what was done, what proves it, what is
open. The ledger is `docs/candidacy/ledger.jsonl`; the method is in
`docs/candidacy.md`; how to add a timed source is `docs/templates/timed_source.md`.
Standing rules: analyzer first, the gate (`tool/gate.sh`) before a commit, nothing
promoted without a ledger entry, no catch-all arms, typed errors, tests where the
behavior is owned (extend, never duplicate), no Co-Authored-By in this repo.

## 2026-11-16

- **Pinned** dartrix to `53c0b0d` (candidacy ledger merged as dartrix #32); claudart
  PR #104 carries the refactor. Suite 5218 tests green.
- **R1 / R1b** (log caps): every one of the seven jsonl logs has the same volume matrix
  in `test/logging/logger_test.dart`; the errors (200) and steps (2000) caps were
  unguarded before. R1 bounded (README listed a removed `performance.md`), R1b proven.
- **R2** (performance): bounded. `TimedSource` reads durations the logs already hold;
  `scanDuration` (no unit) is not read. Gap list reasons are typed.
- **R3 -> R3b** (run row location): the real binary showed run rows going to the global
  log. Fixed through `loggerForProject`; R3 refuted, R3b proven. Gap R22 closed.
- **Equivalents registered:** `logger.dart:552` (>), `timed_source.dart:161` (>).
- **Open:** compiled-binary run for R2 and R3b; volume stress of the timing reader;
  old global rows not moved; weights and factors uncalibrated; dartrix: evidence with a
  commit, `bounded` is terminal; Phases 3 (corpus growth), 5 (topology audit citing
  axioms) and 6 (handoff template, postulates doc, index) not started; T10's 956
  survivors; the deferred items K1-K7, H1-H6, Q10 and the five plan decisions.
