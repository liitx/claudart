# /test_commands — kill and status command test and rule checker

## Module context

**Owns:** `lib/commands/kill.dart`, `test/commands/kill_test.dart`,
`lib/commands/status.dart`, `test/commands/status_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_commands` directly for focused kill and status testing.

---

Scope: `lib/commands/kill.dart`, `test/commands/kill_test.dart`, `lib/commands/status.dart`, `test/commands/status_test.dart`
Run when: any change to `kill.dart`, `kill_test.dart`, `status.dart`, or `status_test.dart`.

---

## Step 1 — Run scoped tests

```
dart test test/commands/kill_test.dart test/commands/status_test.dart \
  --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### status.dart

**Rule: `status` prefers live git branch over handoff branch.**
When `detectGitContext()` succeeds, the live branch should be displayed rather than
the stale branch from the handoff. Only fall back to handoff branch when git is undetectable.
> Check: line 69 must use `currentBranch ?? state.branch`, not just `state.branch`

**Rule: `status` never mutates state.**
Status is read-only. It must not modify the handoff, registry, or any workspace files.
> Check: `grep -n "fileIO.write\|io.write" lib/commands/status.dart` → no results

**Rule: Mismatch warning preserved.**
The warning at lines 78-82 that alerts when current branch differs from handoff branch
must remain — it serves a different purpose (detecting mid-session branch switches).

### kill.dart

**Rule: `kill` never updates skills.md.**
Kill abandons a session — it archives the handoff and removes the symlink.
Knowledge distillation is `teardown`'s responsibility only.
> Check: `grep -n "skills" lib/commands/kill.dart` → no results

**Rule: All destructive operations run inside `withGuard`.**
`closeSession` must always be called from within a `withGuard` call in `kill.dart`.
Guard ownership belongs to the calling command, not to `session_ops.dart`.
> Verified by: success path tests (archive, reset, symlink all succeed atomically)

**Rule: `exit` is injectable — never called as a bare `exit()` inside `runKill`.**
Bare `exit()` terminates the test process. All exit points must use the injected
`exitFn` so tests can assert on exit-path behaviour.
> Check: `grep -n "exit(" lib/commands/kill.dart | grep -v "exit_("` → no results

**Rule: kill tests verify error response, not rollback mechanics.**
When `closeSession` throws, the kill-level test asserts exit code 1.
Rollback mechanics (handoff restored, archive deleted) are verified in
`session_ops_test.dart`. Do not duplicate those assertions here.

**Rule: `kill` uses registry — not legacy path getters.**
Project root → registry lookup → workspace path. No hardcoded paths from
`paths.dart` legacy getters.

---

## Step 3 — Coverage check

| Scenario                                          | Covered |
|---------------------------------------------------|---------|
| status — displays live git branch when available  | ✓       |
| status — falls back to handoff branch when not    | ✓       |
| status — exits 1 when no registry entry           | ✓       |
| status — exits 1 when not in git repo             | ✓       |
| kill — success: archives handoff                  | ✓       |
| kill — success: resets handoff to blank           | ✓       |
| kill — success: removes symlink                   | ✓       |
| kill — success: updates registry lastSession      | ✓       |
| kill — user declines: handoff left intact         | ✓       |
| kill — locked: user declines clear → lock stays   | ✓       |
| kill — locked: user confirms → lock cleared       | ✓       |
| kill — error: exits 1 when closeSession fails     | ✓       |

Flag any gap before marking this module clean.

---

## Step 4 — Report

```
Commands module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  status rules    : ✓ / ✗
  kill rules      : ✓ / ✗
  Coverage gaps   : none / <list>
```
