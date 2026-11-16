BIN     := ~/bin/claudart
ENTRY   := bin/claudart.dart
DART    := dart

.PHONY: ledger ledger-check ledger-baseline impact proof-changed proof-audit diagram gate build test clean rebuild lint analyze check-coverage topology consumer-check ownership liveness spawn-census handoff-consistency leak-check

## Draw the runs a logs directory holds as Mermaid sequence diagrams.
##   make diagram DIR="<global-logs> <workspace-logs>" [CMD=debug] [HTML=<file>]
## or what the tests did:
##   CLAUDART_TEST_TRACE=<file> dart test <files>; make diagram TRACE=<file> [HTML=<file>]
diagram:
	$(DART) run tool/run_diagram.dart $(DIR) $(if $(TRACE),--trace=$(TRACE)) $(if $(CMD),--command=$(CMD)) $(if $(HTML),--html=$(HTML))

## Seed every single-cell change to the handoff transition table in scratch
## copies and log whether the proofs saw it (logs/proofs.jsonl); writes the
## report. Takes about half an hour with 3 workers; never touches the tree.
##   make proof-audit [WORKERS=3] [LIMIT=n] [ONLY=text] [PROOF=transitionTable|closureEvidence|claudartCommand|handoffListeners]
proof-audit:
	$(DART) run tool/proof_audit/run.dart --workers=$(or $(WORKERS),3) --report=docs/topology/proof_audit.md $(if $(LIMIT),--limit=$(LIMIT)) $(if $(ONLY),--only="$(ONLY)") $(if $(PROOF),--proof=$(PROOF))

## The full ledger: every line of every file with a mirrored test mutated, checked
## by that test alone (about an hour with 3 workers). Never touches the tree.
##   make ledger [WORKERS=3]; make ledger-check; make ledger-baseline
ledger:
	$(DART) run tool/proof_audit/run.dart --mutants=lib --mirror-only --workers=$(or $(WORKERS),3) --run-timeout=120 --logs=/tmp/claudart_full_ledger/ws

## Fail if any file has more surviving mutants than the checked-in baseline.
ledger-check:
	$(DART) run tool/proof_audit/ledger_check.dart

## Write down the lower counts of the last full ledger (never raises one).
ledger-baseline:
	$(DART) run tool/proof_audit/ledger_check.dart --write

## Which tests to update when a line changes (from the last ledger run, LOGS
## defaults to the full run's), or that none guards it.
##   make impact TARGET=lib/session/md_io.dart:42 [LOGS=/tmp/claudart_full_ledger/ws]
impact:
	$(DART) run tool/proof_audit/impact.dart --logs=$(or $(LOGS),/tmp/claudart_full_ledger/ws) $(TARGET)

## Re-derive the candidate ledger's "every test can fail" from line mutants: run
## the mutants of each cited lib file (run.dart --mutants=<file> --mirror-only
## --logs=<dir>), then keep the rows on the cited lines.
##   make candidacy-evidence LOGS=<dir>
candidacy-evidence:
	$(DART) run tool/candidacy/evidence_audit.dart --logs=$(LOGS)

## Seed one-line mutants on the lines this change touched (since BASE, default
## main) and fail if a test does not fail for each; the ledger it writes names
## the existing tests a missing assertion belongs with. About 5 s a mutant.
##   make proof-changed [BASE=main] [WORKERS=3]
proof-changed:
	$(DART) run tool/proof_audit/run.dart --mutants=lib --changed-since=$(or $(BASE),main) --workers=$(or $(WORKERS),3) --fail-on-survivors --ledger=/tmp/claudart_proof_changed.md

## Every check a change must pass: suite, analyzer errors, custom_lint. With
## MSG="..." it commits after they pass. See tool/gate.sh.
gate:
	tool/gate.sh "$(MSG)"

## Compile native binary to ~/bin/claudart
build:
	$(DART) compile exe $(ENTRY) -o $(BIN)

## Run all tests with randomized ordering. stdin is /dev/null on purpose: a
## blocking synchronous stdin read cannot be interrupted by a test timeout, so
## a test that reaches an unscripted prompt would hang; at EOF it returns.
test:
	$(DART) test --test-randomize-ordering-seed=random < /dev/null

## Regenerate docs/topology/*.md from the code (the topology test fails when
## the checked-in doc and the code disagree)
topology:
	UPDATE_TOPOLOGY=1 $(DART) test test/topology < /dev/null

## Snapshot of which repo owns which component (claudart, dartrix, zedup are
## expected as sibling checkouts), the names declared in more than one, and the
## tests that assert another repo's component behavior. Read only.
ownership:
	$(DART) run tool/ownership/ownership_scan.dart > docs/topology/ownership.md

## Seed one known defect per shape in a scratch copy and report which tools
## catch it (CAUGHT / MISSED). Read only: the working tree is never touched.
liveness:
	tool/refactor_audit/liveness.sh

## How many saved handoffs disagree with themselves (status ahead of content,
## or content ahead of status). Read only.
##   make handoff-consistency DIR=<a workspace's archive directory>
handoff-consistency:
	$(DART) run tool/refactor_audit/handoff_consistency.dart $(DIR)

## Run the suite with HOME and the workspace root pointed at empty temp
## directories; fails if any test leaves a file there (a seam it did not inject).
leak-check:
	tool/refactor_audit/write_leak_check.sh

## Count git spawns per real command, using the compiled CLI in a throwaway
## project. Read only.
spawn-census:
	tool/refactor_audit/spawn_census.sh

## Replay claudart's lifecycle scenarios against zedup's REAL reader, in a
## throwaway copy of zedup wired to this checkout (neither repo is modified).
## Exit 1 when zedup shows a status claudart's contract says it should not.
##   make consumer-check            (zedup at ../zedup)
##   make consumer-check ZEDUP=/path/to/zedup
consumer-check:
	tool/consumer_check/run.sh $(ZEDUP)

## Run a single test file: make test-file FILE=test/commands/teardown_test.dart
test-file:
	$(DART) test $(FILE) --test-randomize-ordering-seed=random

## Run tests with coverage. One-time fresh-machine setup:
##   dart pub global activate coverage
## Checked up front with a clear message — the bare `dart pub global run`
## failure ("No active package coverage") doesn't say what to run,
## confirmed confusing on a fresh machine by a second agent's cross-machine
## test.
test-coverage:
	@dart pub global list | grep -q '^coverage ' || \
		{ echo "coverage package not activated. Run: dart pub global activate coverage" >&2; exit 2; }
	$(DART) test --coverage=coverage && dart pub global run coverage:format_coverage \
		--lcov --in=coverage --out=coverage/lcov.info --report-on=lib

## Check line coverage against a floor. Depends on test-coverage so
## `make check-coverage` alone always works on a fresh machine, instead of
## failing with "run test-coverage first" — confirmed a real fresh-machine
## footgun by a second agent's cross-machine test.
## 74.0 gives real headroom below this repo's own measured baseline
## (75.9% on one machine, same commit) — a second machine's run came in
## at 75.9% too, but with the lesson from zedup's own floor (set at
## measured - 0.1, broke immediately on another machine) applied here:
## don't set a floor one rounding error away from the actual number.
##
## Update (2026-10-19): measured 86.3% on this commit, so the repo-wide floor
## is 84.0, about two points under it, the same margin rule. The per-directory
## floors guard the logic layers (session, logging, templates, workspace,
## codegen, errors), where a dropped line is a dropped test; lib/ui (45%, raw
## terminal input) and the process-spawning paths are what keep the repo-wide
## number lower, and are deliberately not floored. A directory with no traced
## lines fails the check, so a rename cannot turn a floor into a silent pass.
check-coverage: test-coverage
	$(DART) run tool/check_coverage.dart 84.0 lib/session=93.0 lib/logging=91.0 lib/templates=97.0 lib/workspace=92.0 lib/codegen=91.0 lib/errors=98.0

## Static analysis
analyze:
	$(DART) analyze

## Format check (non-destructive)
lint:
	$(DART) format --output=none --set-exit-if-changed lib/ bin/ test/

## Format in place
fmt:
	$(DART) format lib/ bin/ test/

## Remove compiled binary
clean:
	rm -f $(BIN)

## Clean and rebuild
rebuild: clean build

## Targeted mutation testing -- catches tests that pass but verify nothing
## real (coverage alone can't; confirmed empirically: git_utils.dart's
## detectGitContext() had 100% line coverage via indirect callers but zero
## direct tests, so 10/15 real mutations to it went undetected). Deliberately
## scoped to one file + its own test file per invocation, never the whole
## lib/ tree -- a full-repo run reruns the full suite per mutation point,
## which the package's own docs warn can take hours.
## Usage: make mutation-test FILE=lib/io/git_utils.dart TEST_FILE=test/git_utils_test.dart
##
## DANGER, confirmed real: this tool mutates FILE on disk, runs the test
## command, then reverts it. If the process is killed mid-run (Ctrl-C, a
## tool timeout) the revert never happens and FILE is left mutated and
## committed-looking in your working tree -- happened once while building
## this target (gitEnvClearArgs silently became [] in git_utils.dart,
## which then broke unrelated tests in a confusing way until `git diff`
## revealed the real cause). Always run `git diff FILE` after any run you
## had to interrupt, before trusting anything else in the working tree.
## Update (2026-10-19): the target now snapshots FILE before the run and restores
## it if the run leaves it changed (a killed or interrupted run does not revert
## its mutation, and a mutated line once slipped into a commit that way: the
## performance table's divider row, restored with a test that pins it).
mutation-test:
	@test -n "$(FILE)" || { echo "Usage: make mutation-test FILE=lib/foo.dart TEST_FILE=test/foo_test.dart" >&2; exit 2; }
	@test -n "$(TEST_FILE)" || { echo "Usage: make mutation-test FILE=lib/foo.dart TEST_FILE=test/foo_test.dart" >&2; exit 2; }
	@mkdir -p /tmp/claudart_mutation_test
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<mutations version="1.2">\n' > /tmp/claudart_mutation_test/config.xml
	@cat tool/dart_mutation_rules.xml >> /tmp/claudart_mutation_test/config.xml
	@printf '  <files><file>%s</file></files>\n  <commands><command group="test" expected-return="0" timeout="60">dart test %s</command></commands>\n</mutations>\n' "$(FILE)" "$(TEST_FILE)" >> /tmp/claudart_mutation_test/config.xml
	@cp $(FILE) /tmp/claudart_mutation_test/pre_run.snapshot
	$(DART) run mutation_test -b -f md /tmp/claudart_mutation_test/config.xml; status=$$?; \
	  cmp -s $(FILE) /tmp/claudart_mutation_test/pre_run.snapshot || { \
	    echo "!! $(FILE) was left changed by the run; restored from the snapshot" >&2; \
	    cp /tmp/claudart_mutation_test/pre_run.snapshot $(FILE); }; \
	exit $$status

## Runs mutation_test automatically against every changed lib/ file paired
## with its mirrored test file (same config content as `mutation-test`
## above, generated directly by the script rather than via this target --
## see the script's own header for why), instead of a human naming one pair
## by hand every time. Snapshots each file before its run and restores it
## after pass/fail/timeout/SIGINT/SIGTERM -- issue #77 (mutation_test hangs
## on lib/commands/link.dart specifically; confirmed, reproduced several
## times, not this target's bug to fix) is handled by a per-file timeout
## that kills the whole process tree, not a skip list -- a skip list goes
## stale the moment #77 is fixed upstream, a timeout doesn't.
## Usage: make mutation-test-changed [TIMEOUT_MIN=10]
mutation-test-changed:
	$(DART) run tool/mutation_test_changed.dart $(TIMEOUT_MIN)

## Advisory census: lib/ symbols referenced only from test/, never from real
## lib/ or bin/ code. Always exits 0 -- see the script's own header for why.
test-only-census:
	$(DART) run tool/check_test_only_symbols.dart
