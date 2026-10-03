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
test-coverage:
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
