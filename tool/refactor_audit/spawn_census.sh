#!/bin/zsh
# spawn_census.sh — how many times each real command spawns git.
#
# Compiles the CLI, links a throwaway git project into a temp workspace, and
# runs each command with a `git` shim first on PATH that logs every call and
# delegates to the real git. The compiled binary is used because `dart run`
# itself calls git. Prints `<command> | git spawns=<n>`.
#
#   make spawn-census
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/proj"
REALGIT=$(which git)
cat > "$T/bin/git" <<SHIM
#!/bin/sh
echo "\$*" >> "$T/git_calls.log"
exec $REALGIT "\$@"
SHIM
chmod +x "$T/bin/git"
(cd "$SRC" && dart compile exe bin/claudart.dart -o "$T/claudart" >/dev/null 2>&1) || { echo "compile failed"; exit 1; }
export CLAUDART_WORKSPACE="$T/ws"
cd "$T/proj"
git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
yes x | head -40 | PATH="$T/bin:$PATH" "$T/claudart" link --no-sensitive >/dev/null 2>&1

run() { # label, args...
  label=$1; shift
  : > "$T/git_calls.log"
  PATH="$T/bin:$PATH" "$T/claudart" "$@" </dev/null >/dev/null 2>&1
  echo "$label | git spawns=$(wc -l < "$T/git_calls.log" | tr -d ' ')"
}
run "status" status
run "status --project proj" status --project proj
run "save" save
run "resume" resume
run "preflight suggest" preflight suggest
run "scan" scan
run "report" report
run "doctor" doctor
: > "$T/git_calls.log"
echo '{"tool_name":"Edit","tool_input":{"file_path":"x.dart"}}' | PATH="$T/bin:$PATH" "$T/claudart" hook pre-edit >/dev/null 2>&1
echo "hook pre-edit | git spawns=$(wc -l < "$T/git_calls.log" | tr -d ' ')"
