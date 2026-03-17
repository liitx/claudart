# /test_link — link command test and rule checker

## Module context

**Owns:** `lib/commands/link.dart`, `test/commands/link_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.
Also read when `file_io.dart` or `registry.dart` changes (link is the primary
consumer of both).

**Standalone:** Run `/test_link` directly for focused link and registry-integration testing.

---

Scope: `lib/commands/link.dart`, `test/commands/link_test.dart`
Run when: any change to `link.dart`, `link_test.dart`, `file_io.dart`, or `registry.dart`.

---

## Step 1 — Run scoped tests

```
dart test test/commands/link_test.dart \
  --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### Registry integration

**Rule: `link` is the only command that creates registry entries.**
New `RegistryEntry` instances are only written from `runLink`. No other command
creates entries — `setup`, `teardown`, and `kill` only read or update existing
entries via `touchSession`.

**Rule: Re-linking preserves `createdAt`.**
When a project is already registered, `createdAt` must carry over from the
existing entry. Only `lastSession` and `sensitivityMode` may change on re-link.

**Rule: Registry entries are never duplicated.**
Running `link` twice for the same project root must produce exactly one entry.
`Registry.add()` replaces by name — this is the contract.

### Symlink contract

**Rule: `.claude` symlink points to `<workspace>/.claude/`.**
The symlink is `<projectRoot>/.claude` → `workspaceFor(name)/.claude/`.
No CLAUDE.md symlink is created — that is dc-flutter-specific and does not
belong in claudart.
> Check: `grep -n "CLAUDE.md\|claudeMd" lib/commands/link.dart` → no results

**Rule: Existing symlink is replaced, not accumulated.**
If `.claude` already exists as a symlink, it is deleted before the new one is
created. If it exists as a real file or directory (not a symlink), `link` must
exit with an error rather than overwrite.
> Note: real-file guard is handled at the OS level via `FileIO.linkExists` +
> `FileIO.createLink`. The `MemoryFileIO` in tests does not distinguish
> real files from symlinks — this is verified by the replace test only.

### .gitignore hygiene

**Rule: `.claude` is always added to `.gitignore` after linking.**
`link` must append `.claude` to `<projectRoot>/.gitignore` if not already
present. It must not duplicate an existing entry.

**Rule: Existing `.gitignore` content is never clobbered.**
Append only — all pre-existing entries must survive.

### Sensitivity mode

**Rule: Sensitivity mode is set at link time and stored in the registry.**
`link` is the only place sensitivity mode is configured interactively.
Changing it later requires re-running `link` or a dedicated toggle (not yet
implemented).

**Rule: Sensitivity mode is never changeable during an active session.**
This is enforced at the menu level (`launch.dart`) — `link` itself does not
check session state. Do not add session-state checks to `link.dart`.

### FileIO abstraction

**Rule: `link.dart` uses `FileIO` for all file, directory, and symlink operations.**
No bare `File()`, `Directory()`, or `Link()` calls inside `runLink`.
> Check: `grep -n "File(\|Directory(\|Link(" lib/commands/link.dart` → no results

---

## Step 3 — Coverage check

| Scenario                                        | Covered |
|-------------------------------------------------|---------|
| New project — registry entry created            | ✓       |
| New project — correct projectRoot               | ✓       |
| New project — workspacePath = workspaceFor(name)| ✓       |
| New project — workspace dir created             | ✓       |
| New project — .claude symlink created           | ✓       |
| New project — .gitignore entry added            | ✓       |
| New project — .gitignore not duplicated         | ✓       |
| Sensitivity mode off (user declines)            | ✓       |
| Sensitivity mode on (user accepts)              | ✓       |
| Re-link — no duplicate entry                    | ✓       |
| Re-link — createdAt preserved                   | ✓       |
| Re-link — stale symlink replaced                | ✓       |
| Re-link — sensitivityMode updatable             | ✓       |
| .gitignore created when missing                 | ✓       |
| .gitignore existing content preserved           | ✓       |

---

## Step 4 — Report

```
Link module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  Registry integration rules : ✓ / ✗
  Symlink contract rules      : ✓ / ✗
  .gitignore hygiene rules    : ✓ / ✗
  Sensitivity mode rules      : ✓ / ✗
  FileIO abstraction          : ✓ / ✗
  Coverage gaps               : none / <list>
```
