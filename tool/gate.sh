#!/usr/bin/env bash
# gate — every check a change must pass, in one place, failing on the first
# that does not. With a commit message as the argument it commits (explicit
# paths, never `.claude/`) only after all of them pass.
#
#   tool/gate.sh                    run the checks
#   tool/gate.sh "message"          run them, then commit lib test docs tool
#
# The suite runs with a 4x test timeout: the tests that start real processes
# time out on a loaded machine, and that says nothing about the code.
set -uo pipefail
cd "$(dirname "$0")/.."

make topology >/dev/null 2>&1
make ownership >/dev/null 2>&1

dart test --timeout 4x --test-randomize-ordering-seed=random </dev/null >/tmp/claudart_gate_suite.txt 2>&1
if ! tail -1 /tmp/claudart_gate_suite.txt | grep -q "All tests passed"; then
  echo "SUITE FAIL"
  grep "\[E\]" /tmp/claudart_gate_suite.txt | cut -c1-200 | head -8
  exit 1
fi

errors=$(dart analyze 2>&1 | grep -E "^\s+error" | grep -v analysis_options)
if [ -n "$errors" ]; then echo "ANALYZER FAIL"; echo "$errors" | head -5; exit 1; fi
echo "analyzer: $(dart analyze 2>&1 | tail -1)"

lint=$(dart run custom_lint 2>&1 | tail -1)
if ! echo "$lint" | grep -q "No issues found"; then
  echo "LINT FAIL: $lint"; dart run custom_lint 2>&1 | head -6; exit 1
fi

echo "ALL GATES PASS: $(tail -1 /tmp/claudart_gate_suite.txt | cut -c1-40)"

if [ $# -ge 1 ]; then
  git add lib test docs tool Makefile README.md text bin pubspec.yaml
  git commit -q -m "$1" && git log --oneline | head -1
fi
