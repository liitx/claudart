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
