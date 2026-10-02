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

## Run tests with coverage (requires dart_test coverage support)
test-coverage:
	$(DART) test --coverage=coverage && dart pub global run coverage:format_coverage \
		--lcov --in=coverage --out=coverage/lcov.info --report-on=lib

## Check line coverage against a floor (run test-coverage first).
## 75.8 is this repo's own measured baseline as of 2026-10-02, not a target —
## meant to ratchet up over time, never silently lowered.
check-coverage:
	$(DART) run tool/check_coverage.dart 75.8

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
