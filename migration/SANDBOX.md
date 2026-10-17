# Migration test sandbox

Isolated environment for dry-running `claudart init`/`link`/the eventual
`backup`/`restore` without touching real workspace data or real project
repos. Verified working end-to-end on this machine. Delete alongside the
rest of `migration/` once the real feature ships.

## Setup

```sh
SANDBOX=/tmp/claudart_migration_sandbox
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/workspace"
mkdir -p "$SANDBOX/projects/fake-dart-app"

cd "$SANDBOX/projects/fake-dart-app"
git init -q
git config user.name "Sandbox Tester"
git config user.email "sandbox@test.local"
cat > pubspec.yaml <<'PUB'
name: fake_dart_app
environment:
  sdk: '>=3.0.0 <5.0.0'
PUB
mkdir -p lib
echo "void main() => print('fake app');" > lib/main.dart
git add -A
git commit -q -m "initial fake project"
```

Add more `projects/fake-*` dirs the same way if a scenario needs more than
one registered project (e.g. testing `backup` across a multi-project
registry).

## Running claudart against it

Every command needs `CLAUDART_WORKSPACE` pointed at the sandbox, run from
inside a sandbox project dir:

```sh
export CLAUDART_WORKSPACE=/tmp/claudart_migration_sandbox/workspace
cd /tmp/claudart_migration_sandbox/projects/fake-dart-app
claudart init
claudart link
```

Rebuild the real binary first if testing against uncommitted source changes
(`make build` from the claudart checkout) — the sandbox exercises whatever
`~/bin/claudart` currently points at, same as production use.

## Verified (this machine, 2026-10-08)

`claudart init` + `claudart link` against the sandbox produced a real
workspace: `registry.json`, `skills.md`, `handoff.md`, `archive/`,
`knowledge/generic/{dart.md,testing.md}`, `.claude/commands/*.md`, and a
real symlinked `.claude`/`.cursor/commands` in the fake project. Confirmed
the real `~/.claudart` (doesn't exist on this machine — by design, see
`context_this_machine.md`) and the real
`~/dev/dev_tools/claude/registry.json` (7 entries, unchanged) were
untouched throughout.

## Teardown

```sh
rm -rf /tmp/claudart_migration_sandbox
```

`/tmp` clears on reboot regardless — this is throwaway by design, never
commit anything from inside it.
