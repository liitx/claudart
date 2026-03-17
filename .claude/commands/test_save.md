# /test_save — save command test and rule checker

## Module context

**Owns:** `lib/commands/save.dart`, `lib/commands/save_template.dart`,
`lib/commands/suggest_template.dart`, `lib/commands/debug_template.dart`,
`test/commands/save_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_save` directly for focused save and knowledge-chain testing.

---

Scope: `lib/commands/save.dart`, `test/commands/save_test.dart`
Run when: any change to `save.dart`, `save_test.dart`, `save_template.dart`,
`suggest_template.dart`, or `debug_template.dart`.

---

## Step 1 — Run scoped tests

```
dart test test/commands/save_test.dart \
  --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### Checkpoint contract

**Rule: Every save writes a checkpoint — regardless of session state.**
A checkpoint is written even when root cause is not confirmed and even for a
fresh handoff with no active content. The checkpoint is an audit trail, not a
reward for progress.
> Verified by: `writes checkpoint even when root cause not confirmed`

**Rule: Checkpoint filenames use `checkpoint_` prefix, not `handoff_`.**
This distinguishes checkpoints from teardown archives in the same directory.
`teardown` uses `handoff_<branch>_<ts>.md`; save uses `checkpoint_<branch>_<ts>.md`.
> Check: `grep -n "archiveName\|handoff_" lib/commands/save.dart` → no results

**Rule: Branch name is sanitized in filenames, not in skills entries.**
`feat/audio` → `feat_audio` in the checkpoint filename (filesystem-safe).
`feat/audio` is preserved as-is in skills.md pending entries (human-readable).

**Rule: Multiple saves write multiple distinct checkpoints.**
Each save call produces one new file. Previous checkpoints are never overwritten.
> Verified by: `multiple saves write multiple distinct checkpoints`

### Skills.md pending contract

**Rule: Skills.md pending is updated only when root cause is confirmed.**
"Confirmed" means the root cause field does NOT start with `_Not` or `_Nothing`.
A root cause of `_Not yet determined.` = skipped. Any real text = written.
> Verified by: `returns SkillsUpdateResult.skipped` (unconfirmed group)

**Rule: Hot files entry is written only when `changed` field is confirmed.**
If "What changed (files modified)" is a placeholder, only the root cause entry
is written. No phantom hot files entries.
> Verified by: `root cause entry without changed files writes only one pending entry`

**Rule: `## Pending` section header appears exactly once.**
`appendToSection` creates the section on first write and appends on subsequent
writes. Tests must verify the header does not duplicate across multiple saves.
> Verified by: `Pending section header appears exactly once`

**Rule: Existing skills.md content is never clobbered.**
If skills.md already has content (Hot Paths, Root Cause Patterns, etc.), save
must append to `## Pending` only — all other sections preserved.
> Verified by: `appends to existing skills.md without clobbering`

**Rule: save does NOT write to skills.md when root cause is unconfirmed.**
Not even a placeholder entry. The file must not be created if it didn't exist.
> Verified by: `does not create skills.md when root cause unconfirmed`

### Session integrity

**Rule: save does NOT modify handoff.md.**
The handoff is read but never written by save. Only teardown and the Claude Code
agents write to handoff.md.
> Check: `grep -n "write.*handoff\|handoffPath.*write" lib/commands/save.dart`
> → no results (handoffFile is only used in fileIO.read and fileIO.fileExists)

**Rule: save does NOT remove the .claude symlink.**
Session stays open. Symlink removal is kill/teardown's responsibility.

**Rule: save does NOT acquire the workspace lock.**
Save is a read + append operation. It must not use `withGuard` — locking
would block concurrent save calls and interfere with the session flow.

### Knowledge chain

**Rule: suggest.md instructs users to run `/save` before `/debug`.**
The handshake between suggest and debug is explicit: `/save` locks the confirmed
root cause before debug begins.
> Check: suggest_template.dart Step 4 contains "Run `/save` to checkpoint"

**Rule: debug.md warns when no checkpoint exists.**
If status is `ready-for-debug` but no `checkpoint_*` file is in archive/,
debug must warn the user rather than silently proceeding.
> Check: debug_template.dart Step 1 contains "checkpoint" reference

---

## Step 3 — Coverage check

| Scenario                                               | Covered |
|--------------------------------------------------------|---------|
| Writes exactly one checkpoint file                     | ✓       |
| Checkpoint has `checkpoint_` prefix                    | ✓       |
| Checkpoint filename has sanitised branch (slash → _)   | ✓       |
| Checkpoint filename ends with `.md`                    | ✓       |
| Checkpoint content matches handoff exactly             | ✓       |
| Multiple saves → multiple distinct checkpoints         | ✓       |
| Checkpoint written even for unconfirmed handoff        | ✓       |
| Returns `written` when root cause confirmed            | ✓       |
| Creates skills.md when missing                         | ✓       |
| Pending entry contains branch name                     | ✓       |
| Pending entry contains root cause text                 | ✓       |
| Pending entry contains hot files (changed files named) | ✓       |
| Only one pending entry when no changed files           | ✓       |
| Appends to existing skills.md                          | ✓       |
| Multiple saves accumulate in Pending                   | ✓       |
| `## Pending` header appears exactly once               | ✓       |
| Returns `skipped` when root cause unconfirmed          | ✓       |
| skills.md not created when root cause unconfirmed      | ✓       |
| Existing skills.md untouched when unconfirmed          | ✓       |
| Touches registry lastSession                           | ✓       |
| Exits when project not in registry                     | ✓       |
| Exits when handoff file missing                        | ✓       |
| No skills.md written on error path                     | ✓       |

---

## Step 4 — Report

```
Save module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  Checkpoint contract   : ✓ / ✗
  Skills pending rules  : ✓ / ✗
  Session integrity     : ✓ / ✗
  Knowledge chain       : ✓ / ✗
  Coverage gaps         : none / <list>
```
