#!/bin/zsh
# write_leak_check.sh — does any test write outside its in-memory filesystem?
#
# Runs the whole suite with HOME and CLAUDART_WORKSPACE pointed at empty temp
# directories, then lists every file that appeared there other than Dart's own
# tooling files (pub cache, telemetry). A test that reaches the real filesystem
# through a seam it forgot to inject shows up as a file here, or as a failure.
# Exit 1 when anything leaked. Read only for the repo.
#
#   make leak-check
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd)
G=$(mktemp -d)
trap 'rm -rf "$G"' EXIT
mkdir -p "$G/home" "$G/workspace"
cd "$SRC"
CLAUDART_WORKSPACE="$G/workspace" HOME="$G/home" \
  dart test --test-randomize-ordering-seed=random < /dev/null > "$G/run.txt" 2>&1
tail -1 "$G/run.txt" | cut -c1-80
leaked=$(find "$G/home" "$G/workspace" -type f 2>/dev/null \
  | grep -v '/\.pub-cache/\|/\.dart-tool/\|/\.dartServer/\|/\.config/dart' || true)
if [ -n "$leaked" ]; then
  echo "LEAKED FILES:"; echo "$leaked"; exit 1
fi
echo "no test wrote outside its memory filesystem"
