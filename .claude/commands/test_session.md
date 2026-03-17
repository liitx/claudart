# /test_session — session module test and rule checker

## Module context

**Owns:** `lib/session/workspace_guard.dart`, `lib/session/session_ops.dart`,
`lib/session/session_state.dart`, `lib/session/sync_check.dart`,
`test/session/workspace_guard_test.dart`, `test/session/session_ops_test.dart`,
`test/session/session_state_test.dart`, `test/session/sync_check_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_session` directly for focused session module testing.

---

Scope: `lib/session/`, `test/session/`
Run when: any change to `workspace_guard.dart`, `session_ops.dart`, or their tests.

---

## Step 1 — Run scoped tests

```
dart test test/session/ --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### workspace_guard.dart

**Rule: Lock file is the only mechanism for interrupted state detection.**
No command may check interrupted state by any other means (not config.json,
not handoff status, not symlink presence). `isLocked()` is the single check.

**Rule: Lock file content is the operation name — nothing else.**
`withGuard` writes the operation name string to the lock file.
No JSON, no timestamps, no structured data.

**Rule: Lock is always left on exception.**
`withGuard` must NOT delete the lock if `fn` throws.
The lock surviving an exception IS the interrupted signal.
> Verified by: `withGuard leaves lock file when fn throws`

**Rule: `clearLock` is the only way to remove a stale lock.**
No command deletes the lock file directly. Recovery always goes through
`clearLock` so the action is explicit and auditable.

---

### session_ops.dart

**Rule: Each operation is independently callable.**
`archiveHandoff`, `resetHandoff`, `removeSessionLink` can each be called
alone. `closeSession` composes them — it does not duplicate their logic.

**Rule: `closeSession` is transactional — all or nothing.**
On any step failure, all prior steps must be rolled back before rethrowing.
Rollback order is the reverse of execution order.

Step execution and rollback map:
```
Step 1: archiveHandoff   → fail: throw SessionCloseException('archive')
Step 2: resetHandoff     → fail: delete archive,          throw SessionCloseException('reset')
Step 3: removeSessionLink→ fail: restore handoff, delete archive, throw SessionCloseException('unlink')
```

**Rule: `SessionCloseException.failedStep` names the exact step.**
The string must match one of: `'archive'`, `'reset'`, `'unlink'`.
> Verified by: exception identifies the failed step (×2 rollback tests)

**Rule: session_ops does not call `withGuard`.**
Guard ownership belongs to the calling command, not to ops functions.
`session_ops.dart` must not import `workspace_guard.dart`.
> Check: `grep -n "workspace_guard" lib/session/session_ops.dart` → no results

**Rule: Rollback helpers `_safeDelete` and `_safeWrite` never throw.**
They catch and swallow all exceptions. A rollback failure must never mask
the original failure.

---

### sync_check.dart

**Rule: All check functions are pure — no IO.**
`checkSkillsSync`, `checkHandoffStatus`, `checkCoverageGaps`, and `runPreflight`
take strings as arguments and return values. They must never read files or call
any IO function directly.
> Check: `grep -n "File(\|FileIO\|dart:io" lib/session/sync_check.dart` → no results

**Rule: `SyncCheckResult.merge` is commutative on issue ordering, not semantics.**
The merged result contains all issues from both operands. Severity of each issue
is unchanged. `merge` never deduplicates or re-orders by severity.

**Rule: Warnings never block — errors always block.**
`runPreflight` callers (templates, preflight_cmd) must exit non-zero only on
`hasErrors`, never on `hasWarnings` alone.

**Rule: `checkHandoffStatus('test', ...)` always returns clean.**
The `test` operation has no status gate — it is routing information only.
Any status value must pass without adding an issue.

---

## Step 3 — Coverage check

Every public function in `session_ops.dart` must have tests for:
- [ ] Happy path (correct output/state)
- [ ] Called with no pre-existing state (safe to call on empty workspace)
- [ ] Rollback path (for transactional functions only)

Current coverage map:
| Function             | Happy path | Empty state | Rollback |
|----------------------|-----------|-------------|----------|
| archiveHandoff       | ✓         | n/a         | n/a      |
| resetHandoff         | ✓         | ✓           | n/a      |
| removeSessionLink    | ✓         | ✓ (no link) | n/a      |
| closeSession         | ✓         | —           | ✓ ×2     |

sync_check.dart coverage:

| Scenario                                                      | Covered |
|---------------------------------------------------------------|---------|
| checkSkillsSync — confirmed root cause, pending exists        | ✓       |
| checkSkillsSync — confirmed root cause, no pending entry      | ✓       |
| checkSkillsSync — confirmed root cause, empty skills          | ✓       |
| checkSkillsSync — confirmed root cause, wrong branch pending  | ✓       |
| checkSkillsSync — unconfirmed root cause (placeholder)        | ✓       |
| checkSkillsSync — blank handoff, any skills state             | ✓       |
| checkHandoffStatus — debug, ready-for-debug                   | ✓       |
| checkHandoffStatus — debug, debug-in-progress                 | ✓       |
| checkHandoffStatus — debug, suggest-investigating (error)     | ✓       |
| checkHandoffStatus — debug, needs-suggest (error)             | ✓       |
| checkHandoffStatus — debug, error message mentions /suggest   | ✓       |
| checkHandoffStatus — save, active content                     | ✓       |
| checkHandoffStatus — save, blank handoff (warning)            | ✓       |
| checkHandoffStatus — save, warning mentions claudart setup    | ✓       |
| checkHandoffStatus — test, always clean (all statuses)        | ✓       |
| checkCoverageGaps — all covered                               | ✓       |
| checkCoverageGaps — gaps returned                             | ✓       |
| checkCoverageGaps — mixed table (only gap rows)               | ✓       |
| checkCoverageGaps — empty string                              | ✓       |
| checkCoverageGaps — no table present                          | ✓       |
| runPreflight — test, clean                                    | ✓       |
| runPreflight — test, skills warning                           | ✓       |
| runPreflight — test, coverage warning with filename           | ✓       |
| runPreflight — test, merges skills + coverage warnings        | ✓       |
| runPreflight — debug, clean                                   | ✓       |
| runPreflight — debug, error blocks                            | ✓       |
| runPreflight — debug, error + skills warning both reported    | ✓       |
| SyncCheckResult.isClean with no issues                        | ✓       |
| SyncCheckResult.merge — combines issues from both             | ✓       |
| SyncCheckResult.merge — identity with clean                   | ✓       |

Flag any gap before marking this module clean.

---

## Step 4 — Report

```
Session module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  workspace_guard rules : ✓ / ✗
  session_ops rules     : ✓ / ✗
  Coverage gaps         : none / <list>
```
