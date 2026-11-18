# Candidacy: slice 1 (status enum, candidate ledger, Phase 0 audit, candidate T7)

Owner's direction (2026-11-13): every architectural claim is a falsifiable
candidate that is proven, bounded or refuted on evidence, and only a proven one
becomes an axiom, through a ledger entry. This is slice 1 of the prompt's
Phases 0-6: the machinery to say a candidate's status honestly, and one real
candidate (T7) run through it. Stress/bisect (Phase 3), grading (Phase 4),
topology recommendations (Phase 5) and handoff templates (Phase 6) are later
slices and are not started.

## Terms (as the prompt defines them)

| Term | Meaning |
|---|---|
| Candidate | A falsifiable postulate about a feature, variant or topological relationship |
| Proof | The tests plus mock data showing it holds within the scope of its spec |
| Candidate ledger | Append-only record of every candidate: status, evidence, boundary, justification |
| Axiom | A proven candidate, promoted through a ledger entry |
| Line ledger | What `make ledger` builds today: line mutants and the tests that fail. It is evidence for the candidate ledger, not the same thing |

## Where things live (prompt rule 4: machinery in dartrix, usage in claudart)

| Piece | Home | Why |
|---|---|---|
| `CandidateStatus` enum and its transition rules | dartrix `lib/src/candidacy/` | generic, no claudart types |
| `CandidateLedger` (append-only, validated) | dartrix | pure, in memory, JSON lines in and out; no file I/O |
| `ProofAudit` and `ProofAuditCheck` (Phase 0) | dartrix | generic checklist |
| The candidates, their evidence and the file the ledger is saved to | claudart `docs/candidacy/` | usage |
| Evidence from the line ledger (`proofs.jsonl` rows) | claudart | the rows are claudart's |

dartrix's own rule is that nothing lands without a proving consumer. The owner
directed this addition; claudart is the consumer and T7 is its first use, so the
proving case exists but the dartrix side lands on a branch for the owner to vet.

## The rules the types enforce (compile time where possible, else a refused append)

1. Status moves: `candidate -> underTest -> {proven, bounded, refuted}`;
   `proven -> axiom` only. `bounded` and `refuted` are terminal here (a new
   candidate supersedes them, it does not rewrite them). No other move.
2. `underTest -> proven | bounded` requires a passed Phase 0 audit: all five
   checks `passed` (mocks match spec, deterministic, every test can fail, not
   tautological, variant coverage explicit). Any `failed` or `notChecked` check
   refuses the entry.
3. `proven -> axiom` requires a justification and the threshold the entry states.
4. Every entry names the spec section it rests on, the mock dataset version, and
   at least one piece of evidence unless the status is `candidate`.
5. The ledger is append-only: an entry cannot be changed or removed; an entry
   whose move from the candidate's last status is illegal is refused with a
   typed reason (`LedgerRefusal`), not thrown as a bare exception.
6. A scope claim is explicit: `variantsCovered` and `variantsInSpec` are listed
   by name, so a proof covers no variants beyond the ones it names.

## Pass conditions, defined before the code (each is a test that must fail first)

| # | Condition | Proof |
|---|---|---|
| C1 | Every `(CandidateStatus, CandidateStatus)` pair is classified legal or illegal by a table written out in the test, independent of the enum | matrix test over 6x6 = 36 pairs; one `test()` per pair |
| C2 | `bounded`, `refuted`, `axiom` have no outgoing move (axiom) or only the declared ones | part of C1 |
| C3 | `underTest -> proven` and `-> bounded` are refused unless every `ProofAuditCheck` is `passed`; one test per check, each failing the other four passed | 5 checks x 2 target statuses |
| C4 | `proven -> axiom` is refused without a justification | one test |
| C5 | An entry for an unknown first status (not `candidate`) is refused | one test |
| C6 | Append-only: the list of entries a ledger exposes cannot be mutated; appending never changes earlier entries | two tests |
| C7 | JSON lines round trip: write then parse returns equal entries; a line with an unknown status name is refused as `unknownStatus`, not defaulted | one per field plus the unknown case |
| C8 | Seeded faults: for each rule above, a weakened ledger (a rule removed) fails a named test; recorded with `proofs.jsonl` rows through claudart's audit afterwards | mutation run on the new files, survivors zero or registered |
| C10 | `proven` covers every variant the spec names; a partial proof is `bounded`, and a claim that covers a variant outside the spec is refused | three tests (covers outside spec, proven missing a variant, bounded partial accepted) |
| C9 | T7 as a candidate: its ledger entries cite the register row, the spec (`docs/methodical_refactor.md` T7 and "perspectives"), neighbors (`teardown`, `status`, `matrix_consumers_test`), the refuting result, and Phase 0 findings for its mocks | a claudart test that loads `docs/candidacy/*.jsonl`, parses with dartrix's ledger, and fails on a refused entry |

## Phase 0 for T7's mocks (what is verified, not assumed)

The mocks under T7 are `SessionState` fixtures in `test/session/closure_evidence_test.dart`
and the status/teardown tests. Phase 0 is run by reading them against the spec and
by seeded faults, and the result is logged in the candidate ledger. A mock that
mirrors its assertion, or a variant with no fixture, is recorded as a finding and
blocks `proven`.

## Candidate T7

"For every `ClosureEvidence` value, the action `teardown --headless` takes equals
`automaticClosureFor(evidence)`." Today this is false for two values
(`debugUnrecorded`, `none`), so the candidate starts `underTest` and the expected
first result is `refuted` or `bounded` until the owner decides the intended action
(T7 in the register). The candidate does not decide it; it states the claim and
records that it fails, which is the honest ledger entry.

## Order

1. This document. 2. dartrix tests for C1-C7 (red). 3. dartrix types (green).
4. dartrix analyzer, suite, mutation on the new files. 5. claudart: T7 entries,
C9 test, docs. 6. Commit each repo locally, no push.

## Result of slice 1 (2026-11-13)

| Condition | Result |
|---|---|
| C1-C7, C10 | dartrix `test/candidacy/` (206 tests; the full suite is 311): every status pair, every audit check against `proven` and `bounded`, every refusal, append-only, JSON lines |
| C8 | line mutants of the four new files, run with this repository's ledger on dartrix: 38 caught, 0 missed, 17 invalid (they do not compile: null checks the type system enforces). The first run left one survivor, the optional-field type check; a test was added to the entry's own test file, not a new one |
| C9 | `test/topology/candidacy_ledger_test.dart` reads `docs/candidacy/ledger.jsonl` with dartrix's ledger and fails on a refused line, on a status that differs from the one written in the test, and on evidence that names a file or text that is not there; two seeded edits of the ledger file were each caught |

**T7 is `refuted`, with its boundary.** The claim ("what `teardown --headless` does
equals `automaticClosureFor`") holds for `verified` and `confirmedBySuggest` and is
false for `debugUnrecorded` and `none`. Phase 0 of its mocks found two things: the
test `has an automatic closure` asserts that the result is a member of its own return
type, so it can never fail (`noTautologicalMock` failed); and the headless teardown
cases have no `none` case. The ledger therefore refuses `bounded` for T7 even though
it holds for two values, which is the rule working: a proof on mocks that failed
Phase 0 is not a proof. Both findings are open work on T7's tests, listed in the
ledger entry. The owner's decision on the intended action (register row T7) is still
what moves it forward; it will be a new candidate, not an edit of this one.

**Assumptions logged, not hidden:**
- The ledger refuses a repeated status (`underTest` twice). Re-running a proof and
  scoring convergence (Phase 4) needs repeated entries; that is slice 2 and changes
  this rule on purpose.
- dartrix's own rule is that nothing lands without a proving consumer. T7 is the
  consumer, but the owner should vet the dartrix branch before it is pushed.
- claudart reads dartrix through a git dependency, so until the dartrix branch is
  pushed this repository needs an untracked `pubspec_overrides.yaml` pointing at
  `../dartrix`; without it `test/topology/candidacy_ledger_test.dart` does not
  compile. The file is deliberately not committed.
- The audit outcomes in the T7 entries were set by reading the mocks and the
  recorded runs; nothing yet derives them. Deriving `everyTestCanFail` from
  `proofs.jsonl` rows is the next link between the line ledger and this one.

## T7's Phase 0 findings, closed (2026-11-16)

Both findings in T7's ledger entry were closed in the tests that already own the
behavior, none added beside them: `closure_evidence_test.dart` lost `has an automatic
closure` (the evidence matrix above it already has one row per value, and the test
could not fail), and the headless teardown cases in `teardown_test.dart` gained the
`none` case. A seeded change that makes headless teardown treat `none` as verified
fails that case and only that case. The T7 entry stays `refuted`: the ledger is
append-only and the claim is still false for `debugUnrecorded` and `none` until the
owner decides the intended action; the mocks are now fit to prove the claim that
follows that decision.

## Deriving `everyTestCanFail` from the line ledger (2026-11-16)

A ledger entry's outcome for `everyTestCanFail` is no longer only read off by hand.
`make candidacy-evidence LOGS=<dir>` keeps, for each `lib/` line an entry cites, the
verdict of every one-line mutant the line ledger ran on it
(`docs/candidacy/evidence_rows.jsonl`). `test/topology/candidacy_evidence_test.dart`
derives the outcome by a written-out rule (no judged mutant: not checked; any missed:
failed; else passed), fails when a recorded outcome differs from the derived one, and
fails when a cited line no longer reads as it did when the mutants ran. Two seeded
edits of the snapshot (a verdict, a line's text) were each caught.

**Closed the same day:** the derivation reads every audit row on a cited line, a
line mutant or a matrix fault alike (`closureEvidence`: 29 faults, 29 caught). T7's
cited `closure_evidence.dart` lines now have rows (6 matrix faults on the two arms
it cites, all caught) beside the one teardown mutant, so the recorded `passed` is
derived end to end. One seeded edit (a matrix row marked missed) fails the
consistency test.

**What this does and does not prove, stated plainly (as first written, before the
matrix rows were read; the table lines are no longer the gap):** T7 cites one mutable line
(`teardown.dart`, the headless decision): its mutant is caught, so the recorded
`passed` is now derived. The cited lines of `closure_evidence.dart` are switch arms
that no line operator mutates; the table is guarded by the matrix audit's 29 seeded
faults instead, which this derivation does not read. So a line-ledger outcome covers
only lines the operators can mutate; the next link is reading the matrix audit's rows
the same way. While deriving, a scratch copy of this repository failed to resolve a
local `pubspec_overrides.yaml` path; the audit now makes such paths absolute, tested.

# Slice 2: repeated entries, confidence, boundary search (2026-11-16)

Phase 3 (find where a candidate breaks) and Phase 4 (grade it, flag a stall). Machinery
in dartrix, first use in claudart after it is proven. Corpus growth, topology
recommendations and handoff templates stay later slices.

## What changes, and the assumptions it logs

| Piece | Rule |
|---|---|
| Re-test | `underTest -> underTest` is legal: a proof is re-run as the code or the corpus changes, and each run is an entry. (Slice 1 refused it on purpose; this is the planned change.) |
| Factors | An entry carries three measured factors in 0..1: `boundary` (normalized), `topologyReach` (neighbors confirmed / named), `impact` (duplication or dead paths removed). A fourth, variant coverage, is **derived** from the entry's own variant lists, never stored, so it cannot be made up. |
| Confidence | `w1*coverage + w2*boundary + w3*reach + w4*impact`, weights sum to 1. Initial weights 0.4, 0.2, 0.2, 0.2 are an **assumption**: coverage of the spec is the claim itself, so it weighs most; the rest are equal until a calibration against seeded faults says otherwise (not done: logged, not hidden). |
| Required factors | `proven`, `bounded` and `axiom` need factors; `refuted` and `candidate` do not; a re-test may carry them. |
| Axiom threshold | A number in 0..1 the entry states; the axiom's computed confidence must be at least it. The justification says why that threshold. |
| Trend | Over a candidate's entries that carry factors: `rising`, `stalled` (equal), `dropped`, or `notEnoughHistory`. A stalled or dropped candidate is listed as flagged. A drop is accepted (it is data) and flagged. |
| Boundary search | Given ascending complexity levels and a predicate, bisect to the highest level that holds and the lowest that fails; report "never broke" when the top holds, "never held" when the bottom fails. It assumes holding is monotone in level; a separate check finds a level that holds after one that failed, and that is recorded as a refuted assumption. |

## Pass conditions (tests first)

| # | Condition |
|---|---|
| D1 | The legal-move table of the status test gains `underTest -> underTest`; every pair is still classified by a table written out in the test |
| D2 | Confidence equals the written-out weighted sum for a table of factor sets; weights that do not sum to 1 are refused at construction |
| D3 | Variant coverage as a factor is the covered fraction of the spec's variants; an empty spec counts as 1 only when nothing is covered outside it |
| D4 | One refusal per new rule: factors missing, a factor outside 0..1, threshold outside 0..1, confidence below the stated threshold |
| D5 | Trend over a table of confidence series: none, one, rising, equal, falling, and a series whose last step differs from earlier ones |
| D6 | Boundary search over a table of predicates (all hold, none hold, boundary at each position of a small level list, one level), with the number of evaluations bounded by log2(n)+2; non-monotone predicates are found by the monotonicity check and not hidden |
| D7 | JSON: factors and numeric threshold round trip; a mistyped factor is malformed |
| D8 | Line mutants of the changed and new dartrix files: none missed, or accepted with a reason |

## Result of slice 2 (2026-11-16)

| Condition | Result |
|---|---|
| D1-D7 | dartrix `test/candidacy/` (322 tests, suite 427): the legal-move table with `underTest -> underTest`, the confidence sum for a table of factor sets, the derived coverage, one refusal per new rule, the trend over a table of series, bisecting over a table of predicates with the run count of each worked out by hand, the monotone check, JSON round trips |
| D8 | line mutants of the candidacy files: 97 caught, 26 invalid (do not compile), 3 missed and registered as equivalent in `docs/topology/ledger/dartrix_equivalents.txt` with reasons (an exact-tolerance comparison no floating point test can reach, and a `>=` after the equal case was already handled). The first run missed nine: six were closed by tests added to the files that already hold those groups (an exact run count per boundary case, weight 0, a tolerance on either side, thresholds 0 and 1), three were these |

The run count test is the one that mattered: the bound I first wrote (log2(n)+2) let
a mutant that makes the search probe one extra level pass; the exact hand-derived
count kills it.

**Assumptions logged, not hidden.** The initial weights (0.4, 0.2, 0.2, 0.2) are not
calibrated; calibrating them means taking candidates whose truth is known (a seeded
fault, a refuted claim) and checking that the score separates them, which needs more
candidates than the ledger has. The boundary search assumes holding is monotone in the
level, and `firstNonMonotone` is how a candidate checks that instead of trusting it.
The ledger's `confidenceBelowThreshold` compares floating point values without a
tolerance; a threshold of exactly 1 with every factor at 1 was tested and accepted,
and a case that fails by rounding would show up as a refused axiom, not a wrong one.

**Not yet used on a claudart candidate.** The machinery is proven on its own tests;
its first real use needs a candidate with a complexity axis whose truth is not known in
advance. The candidate that fits best is "every log keeps its retention cap at any
volume" (axis: entries written, in multiples of the cap), because the code, the
existing cap matrix in `test/logging/logger_test.dart` and an obvious breaking point
(the trim slack of 50 lines) all exist. Running it extends that matrix's levels rather
than adding a test beside it.

# Candidate R1: every log keeps its cap at any volume (2026-11-16)

The first candidate run end to end with the machinery, and the first use of the
stress and bounds phase on claudart's own logs. It supports the audit logs the
architecture work reads (`docs/methodical_refactor.md` reads logs as the
expected-versus-actual record, so a log that silently loses or keeps the wrong rows
breaks every proof that reads it).

## The postulate

For every log the README table gives a cap (`README.md`, "Each workspace keeps its
own logs"), at any number of lines already written and after any number of writes,
the file holds exactly what the trim rule says: a jsonl log may run 50 lines past its
cap and is then cut back to the cap; `errors.jsonl` (rewritten on each error,
deduplicated by fingerprint) is cut to the cap with no slack. What is kept is the
newest rows, in order; a repeated error is counted, not added.

## What the spec needs from the mocks (Phase 0, before any test was changed)

| Need | Why | Held before? |
|---|---|---|
| One writer per log named in the spec (7 jsonl logs) | A cap is per log; a log with no writer in a test is unproven | No: 4 of 7 (interactions, transitions, gates, proofs); errors, steps absent from the matrix, models in a separate test |
| A volume axis around each boundary: below the cap, at it, at cap + 49 (no trim), at cap + 50 (first trim), far past it | The rule changes at exactly those points | Partly: cap + 49 and cap + 51 only |
| Several writes, not one | The trim cycle (grow 50, cut) is only seen across writes | No (interactions only, single write) |
| Rows that identify themselves | "Newest kept, in order" cannot be seen from a length | No: three of the four matrix logs asserted length only |
| Expected counts written from the spec, not computed by the code under test | A mock that mirrors the code proves nothing | Yes (hand-written), kept |
| A repeat of an error already held, at the cap | Dedup must not drop or grow the file | No |
| The README row for each log states its cap | The spec must say what the test says | No: `proofs.jsonl` had none; fixed |

Verified by seeding faults, not by reading: with the old tests a change of the errors
cap (200), of the steps cap (2000) and of the errors trim all passed every test.

## What changed, in the tests that own the behavior

`test/logging/logger_test.dart`: the log-cap matrix now covers all seven jsonl logs
(13 volume and write-count cases each, expected counts and surviving rows written by
hand), with a separate matrix for `errors.jsonl`. The three tests that covered one
log's cap alone (interactions twice, models once) were removed: the matrix covers
those cases, so keeping them would be duplicates.

## Results

- 16 hand-seeded faults on the trim and caps (every cap, the slack both ways, the
  comparison at the slack, which end is kept, the blank-line filter, the errors trim
  disabled or keeping the oldest): all caught except `>` to `>=` at the errors trim,
  which is equivalent (`sublist(length - cap)` is the whole list when the length is
  the cap) and is registered with that reason.
- Candidate R1 is recorded as `bounded`, not `proven`: `performance.md` is in the
  README table with a cap of 50 and has no writer, so one of the eight spec variants
  cannot be covered. Boundary: up to 10 times the cap in one write and 160 writes
  from the cap; concurrency is tested only at small volume.

## Assumptions logged

- The confidence factors for R1 (boundary 0.7, topology reach 0.875 = 7 of 8
  variants, impact 0.5) are judgments, as are the weights; neither is calibrated yet.
- The monotone assumption of boundary search was not needed: the trim rule has
  known thresholds, so the volume axis is written out, not bisected. Bisection is
  for the first claim whose threshold is not known in advance.
- The global planner log and `performance.md` are outside this candidate.

## What R1 added to the machinery

- The derived `everyTestCanFail` no longer counts a mutant the accepted-equivalents
  registry names (file, line, operator): that mutant is the same program, so no test
  could fail on it. It is not judged; a different operator, line or file still is.
  Needed because R1's cited errors-trim line has exactly one such mutant. Five
  cases in `candidacy_evidence_test.dart` pin the three dimensions.
- R1's snapshot rows come from a `run.dart --mutants=lib/logging/logger.dart
  --mirror-only` run (40 caught, 5 missed, 5 invalid of 50): on the six cited
  lines every judged mutant is caught except the registered equivalent. The other
  misses (`logSchemaVersion`, two optional-field guards, the error count seed) are
  outside R1's lines and stay in the survivors ledger.

# R1b and R2: performance is derived, not a second log (2026-11-16)

R1 was bounded only because the README listed `performance.md`, a log removed on
2026-11-06 (methodical_refactor S9, closed by removal; each run's `durationMs`
is on its interactions row). The owner chose to derive performance from the logs
that already hold durations. The stale rows are gone from the README, and:

- **R1b** (proven) restates R1 under the corrected spec. A bounded candidate cannot
  move, so a corrected spec is a new candidate; R1 stays as the record.
- **R2** (bounded): every log is either read for timing or proven to hold no
  duration-like field, and every timed row reads as a record or a named gap.
  `scanDuration` (fractional, no unit) is the one timing not read; the spec says so,
  which is why R2 is bounded and not proven.

What was built (enum driven, each piece with its proof written first):
`TimedSource` (four variants; `logFile`, `qualifies`, `rawDurationOf` and `labelOf`
are exhaustive switches with no default arm), `readTimedLog` (records and gaps, a gap
carries its reason), `summarizeTimed`, a Timing block in `claudart status`, the
template `docs/templates/timed_source.md`, and a fault provider for the `logFile`
table (28 faults, all caught; the matrix rule requires every decision table to be
audited). Three guards fired during the build and each pointed at a real slip: a log
file name spelled in a test, a test title naming a type as text, and the unaudited
table. The gate also found two survivors: a duration of zero had no test (added), and
a comparison of two equal durations is equivalent (registered).

## The procedure, as it was followed (the template for the next candidate)

1. **State** the postulate and the spec section it is about; append a `candidate` entry.
2. **List what the spec needs from the mocks** (one writer per variant, the axis
   around each boundary, rows that identify themselves, expected values written by
   hand) and mark which the existing tests already hold. Seed faults against the
   existing tests: a fault no test catches is a Phase 0 finding.
3. **Fix the spec if the spec is wrong** (stale README rows) before testing it.
4. **Change the tests that own the behavior**, not a new file: extend the matrix,
   remove the tests the matrix now duplicates.
5. **Build with the enum first**: the compiler lists what a new variant must answer;
   the template says how to add one.
6. **Run the gate**: analyzer, suite, lint and a mutant of every touched lib line;
   every decision table audited. Close survivors in the tests that own the line, or
   register an equivalent with its reason.
7. **Derive the evidence**: run the mutants of the cited files, snapshot the rows on
   the cited lines, append `underTest` with the audit, then the result
   (`proven`, `bounded` with its boundary, or `refuted`) with factors.
8. **Log the assumptions** (weights, factors, anything not measured).

Not yet done for these two: volume stress of the timing reader, and a run of the
installed binary (`claudart status` over a real workspace), which a candidate that
claims the real log format should have.

## R22 closed: R3b (2026-11-16)

The run row now goes through `loggerForProject`, the same choice the failure boundary
makes. Real binary, before and after: `claudart status` wrote its run row to the
global log (0 rows in the workspace); after, 1 row in the workspace log and a Timing
block in the output. R3b is proven for the spec as written. Two things it cost:

- Two CLI tests expected exactly one row; a command now leaves its own outcome row
  and then the boundary's run row, and they say so.
- The line mutants of the new function's null checks cannot be judged (a flipped
  check breaks the null promotion on the next line, so the mutant does not compile).
  The choice is audited by seven hand-seeded faults instead (`ProjectLoggerFaults`).

**A limit of the ledger found here, not fixed:** evidence is `path :: text` with no
commit, so once a refuted candidate's bug is fixed the code it cited is gone and the
citation test fails. R3's evidence was rewritten once to cite what still exists (the
spec, the gap row, the test that now guards the fix). A durable fix is dartrix's: an
evidence citation that carries the commit it was true at.

# Phase 5: what the topology rests on, so far (2026-11-16)

Cites only what the ledger holds (`docs/candidacy/index.md`). No axiom exists yet, so
nothing below is stated as an axiom; each line says what a proven or bounded
candidate supports and what is left on trust.

| Topology claim | Supported by | Standing | Still on trust |
|---|---|---|---|
| Every log keeps its documented cap, newest rows, in order | R1b | proven | concurrency at volume; the global planner log |
| Every log's timing is read or proven absent; a row is a record or a named gap | R2 | bounded | `scanDuration` has no unit, so it is not read |
| A command's run row lands in its project's logs, through one logger choice | R3b | proven | rows written before this change sit in the global log |
| `teardown --headless` does what `automaticClosureFor` says | T7 | refuted for `debugUnrecorded` and `none` | the intended action is the owner's decision |

What this says about the state-driven plan: the log layer, which every later proof
reads as the expected-versus-actual record, now has a proven shape (R1b, R3b) and a
typed way to read timing (R2). The handoff state machine's own cells have no
candidate yet except T7; the next candidates belong to the matrix of
`HandoffStatus` x `HandoffEvent` (the lifecycle conformance test is their mock
data). Nothing on that side is proven by this ledger, whatever the tests say.
