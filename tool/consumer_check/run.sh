#!/usr/bin/env bash
# consumer_check — does zedup read claudart's handoff state the way claudart's
# contract says? Replays claudart's lifecycle scenarios (test/conformance)
# against zedup's REAL reader, in a throwaway copy of zedup wired to THIS
# claudart checkout. Neither real repo is modified.
#
#   tool/consumer_check/run.sh [path-to-zedup]      (default: ../zedup)
#   KEEP=1 tool/consumer_check/run.sh               keep the temp copy
#
# Exit 0: zedup agrees on every step. Exit 1: it disagrees somewhere.
set -euo pipefail

CLAUDART="$(cd "$(dirname "$0")/../.." && pwd)"
ZEDUP="${1:-$CLAUDART/../zedup}"
[ -f "$ZEDUP/pubspec.yaml" ] || { echo "no zedup at $ZEDUP"; exit 2; }

WORK="$(mktemp -d /tmp/claudart_consumer_check.XXXXXX)"
[ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$WORK"' EXIT

rsync -a --exclude .dart_tool --exclude build --exclude .git --exclude .DS_Store \
  "$ZEDUP"/ "$WORK/zedup/"
cd "$WORK/zedup"

if grep -q '^dependency_overrides:' pubspec.yaml; then
  echo "zedup already has dependency_overrides; merge claudart's by hand" >&2
  exit 2
fi
cat >> pubspec.yaml <<OVERRIDES

dependency_overrides:
  claudart:
    path: $CLAUDART
  claudart_lints:
    path: $CLAUDART/tool/claudart_lints
OVERRIDES

mkdir -p tool/cc/conformance tool/cc/helpers
cp "$CLAUDART/test/conformance/lifecycle_scenarios.dart" tool/cc/conformance/
cp "$CLAUDART/test/helpers/mocks.dart" tool/cc/helpers/
cp "$CLAUDART/tool/consumer_check/consumer_check.dart.tmpl" tool/cc/consumer_check.dart

dart pub get > /dev/null
dart run tool/cc/consumer_check.dart
