BIN     := ~/bin/claudart
ENTRY   := bin/claudart.dart
DART    := dart

.PHONY: build test clean rebuild lint analyze check-coverage

## Compile native binary to ~/bin/claudart
build:
	$(DART) compile exe $(ENTRY) -o $(BIN)

## Run all tests with randomized ordering
test:
	$(DART) test --test-randomize-ordering-seed=random

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
check-coverage: test-coverage
	$(DART) run tool/check_coverage.dart 74.0

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
## Usage: make mutation-test FILE=lib/git_utils.dart TEST_FILE=test/git_utils_test.dart
##
## DANGER, confirmed real: this tool mutates FILE on disk, runs the test
## command, then reverts it. If the process is killed mid-run (Ctrl-C, a
## tool timeout) the revert never happens and FILE is left mutated and
## committed-looking in your working tree -- happened once while building
## this target (gitEnvClearArgs silently became [] in git_utils.dart,
## which then broke unrelated tests in a confusing way until `git diff`
## revealed the real cause). Always run `git diff FILE` after any run you
## had to interrupt, before trusting anything else in the working tree.
mutation-test:
	@test -n "$(FILE)" || { echo "Usage: make mutation-test FILE=lib/foo.dart TEST_FILE=test/foo_test.dart" >&2; exit 2; }
	@test -n "$(TEST_FILE)" || { echo "Usage: make mutation-test FILE=lib/foo.dart TEST_FILE=test/foo_test.dart" >&2; exit 2; }
	@mkdir -p /tmp/claudart_mutation_test
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<mutations version="1.2">\n  <files><file>%s</file></files>\n  <commands><command group="test" expected-return="0" timeout="60">dart test %s</command></commands>\n</mutations>\n' "$(FILE)" "$(TEST_FILE)" > /tmp/claudart_mutation_test/config.xml
	$(DART) run mutation_test -b -f md /tmp/claudart_mutation_test/config.xml

## Runs `mutation-test` automatically against every changed lib/ file paired
## with its mirrored test file, instead of a human naming one pair by hand
## every time. Snapshots each file before its run and restores it after
## pass/fail/timeout/interrupt -- issue #77 (mutation_test hangs on
## lib/commands/link.dart specifically; confirmed, reproduced 3 times, not
## this target's bug to fix) is handled by a per-file timeout that kills the
## whole process tree, not a skip list -- a skip list goes stale the moment
## #77 is fixed upstream, a timeout doesn't.
## Usage: make mutation-test-changed [TIMEOUT_MIN=10]
mutation-test-changed:
	$(DART) run tool/mutation_test_changed.dart $(TIMEOUT_MIN)

## Advisory census: lib/ symbols referenced only from test/, never from real
## lib/ or bin/ code. Always exits 0 -- see the script's own header for why.
test-only-census:
	$(DART) run tool/check_test_only_symbols.dart
