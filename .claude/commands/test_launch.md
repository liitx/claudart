# /test_launch — launcher module test and rule checker

## Module context

**Owns:** `lib/commands/launch.dart`, `test/commands/launch_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_launch` directly for focused launcher testing.

---

Scope: `lib/commands/launch.dart`, `test/commands/launch_test.dart`
Run when: any change to `launch.dart` or `launch_test.dart`.

---

## Step 1 — Run scoped tests

```
dart test test/commands/launch_test.dart \
  --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### Phase separation

**Rule: Phase 1 loads only the registry — nothing else.**
Before the user selects a project, `launch.dart` must not read any workspace
file (handoff, config, lock). Only `Registry.load()` and `isLocked()` (which
reads a single lock file path) are permitted.
> Check: no `handoffPathFor`, `configPathFor`, or `skillsPathFor` calls before
> the user's project selection resolves.

**Rule: Phase 2 loads workspace data only for the selected project.**
Handoff, session state, and lock status are loaded once after selection.
No eager loading of all workspaces upfront.

### Registry as the only index

**Rule: Project list comes from `Registry.load()` — no filesystem scanning.**
`launch.dart` must not use `Directory.listSync()` or any glob to discover
projects.
> Check: `grep -n "listSync\|Directory(" lib/commands/launch.dart` → no results
> (except inside helpers that are never called in Phase 1).

### Sensitivity mode

**Rule: Sensitivity mode is shown inline in the project list with an OSC 8 hyperlink.**
When `entry.sensitivityMode == true`, the list row must include the ANSI
hyperlink pointing to the README sensitivity section. This is display-only —
the mode itself is not changeable from the launcher.

**Rule: Sensitivity mode is never changeable from an active session.**
No launcher path may change `sensitivityMode` while a handoff exists with
`hasActiveContent == true`. Mode changes are a separate command (not yet
implemented).

### Injection contract

**Rule: All user input goes through `pickFn` — no bare `stdin.readLineSync()` inside `runLauncher`.**
`stdin` is only used in `_defaultPick`, which is the production fallback.
Tests always inject `pickFn`.

**Rule: `confirmFn` is threaded through to `runKill` — never bypassed.**
When `runLauncher` routes to `runKill`, it must pass its own `confirmFn` so
tests can control kill confirmations without reading stdin.

**Rule: `exit` is injectable — never called as bare `exit()` inside `runLauncher`.**
All exit points inside `runLauncher` must use `exit_` (the injected fn).
> Check: `grep -n "exit(" lib/commands/launch.dart | grep -v "exit_("` → no results

### Menu selector constants

**Rule: Tests must reference named menu selectors — never magic numbers.**
`launch.dart` exports named constants for every menu context:
- `registerChoice(entryCount)` — dynamic; derived from registry size
- `lockedMenuKill`, `lockedMenuBack` — locked-workspace menu
- `activeMenuResume`, `activeMenuKill`, `activeMenuBack` — active-session menu
- `freshMenuStart`, `freshMenuBack` — fresh-workspace menu

Any `pickFn` returning a bare integer literal (e.g. `return 2`) in
`launch_test.dart` is a violation. The named constant must be used instead.

**Rule: When a new menu option is added to `launch.dart`, its named constant must be added in the same commit.**
The constant is the contract between production code and tests. Adding a menu
action without a corresponding constant breaks the selector pattern.
> Check: every integer in `pickFn` calls in `launch_test.dart` is a named constant
> `grep -n "return [0-9]" test/commands/launch_test.dart` → only `return 1` (project selection, always first) is acceptable

---

## Step 3 — Coverage check

| Scenario                                            | Covered |
|-----------------------------------------------------|---------|
| Empty registry → exits with message                 | ✓       |
| Project list shown without error                    | ✓       |
| Current project highlighted (cwd matches)           | ✓       |
| Sensitivity mode displayed without crash            | ✓       |
| Locked workspace → kill menu offered                | ✓       |
| Locked workspace → Back leaves lock intact          | ✓       |
| Active session → Kill archives and removes symlink  | ✓       |
| Active session → Resume prints instructions only    | ✓       |
| Fresh workspace → Back leaves archive empty         | ✓       |
| Register current dir (runLink call)                 | —       |

Note: the "Register" path is not unit-tested here because `runLink` has not
yet been migrated to accept injectable IO. Flag this gap when `link.dart` is
updated.

---

## Step 4 — Report

```
Launch module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  Phase separation rules  : ✓ / ✗
  Registry-only index     : ✓ / ✗
  Sensitivity display     : ✓ / ✗
  Injection contract      : ✓ / ✗
  Menu selector constants : ✓ / ✗
  Coverage gaps           : none / Register path (link.dart migration pending)
```
