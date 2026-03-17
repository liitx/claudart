# /test — claudart test orchestrator

Full suite runner and global rule enforcer.
Reads feature test files directly to execute their scoped tests and rules inline,
then runs the complete suite with a randomized seed as the final gate.

When to run automatically:
- Any change to `lib/` or `test/`
- Before suggesting a commit message
- After resolving a test failure

---

## Step 0 — Preflight sync check

Before running any tests, verify the workspace is in a consistent state.

```
claudart preflight test
```

- `✓ Preflight clean` — proceed to Step 1.
- `⚠ warnings` — list them in the final report, but proceed. Do not block.
- `✗ errors` — stop. Report the error. Do not run tests until resolved.

The preflight checks:
1. **Skills sync** — if a root cause is confirmed in the handoff, a pending entry must exist in skills.md. A missing entry means `/save` was not run after `/suggest` wrote KT.
2. **Coverage gaps** — any `—` row in a coverage table is a declared gap. Flag each one by filename and scenario name.

---

## Step 1 — Detect scope and execute feature tests inline

Check which files changed (via git diff or recent edits). Find the matching
feature test file below, **read it**, and execute its Step 1 (scoped dart test
command) and Step 2 (module rules) inline before proceeding to the full suite.

| Changed path                          | Read this file                            |
|---------------------------------------|-------------------------------------------|
| `README.md`                           | `.claude/commands/test_readme.md`         |
| `test/readme_sync_test.dart`          | `.claude/commands/test_readme.md`         |
| `lib/session/workspace_guard.dart`    | `.claude/commands/test_session.md`        |
| `lib/session/session_ops.dart`        | `.claude/commands/test_session.md`        |
| `lib/session/sync_check.dart`         | `.claude/commands/test_session.md`        |
| `test/session/`                       | `.claude/commands/test_session.md`        |
| `lib/registry.dart`                   | `.claude/commands/test_registry.md`       |
| `lib/paths.dart`                      | `.claude/commands/test_registry.md`       |
| `test/registry_test.dart`             | `.claude/commands/test_registry.md`       |
| `lib/commands/save.dart`              | `.claude/commands/test_save.md`           |
| `lib/commands/save_template.dart`     | `.claude/commands/test_save.md`           |
| `lib/commands/suggest_template.dart`  | `.claude/commands/test_save.md`           |
| `lib/commands/debug_template.dart`    | `.claude/commands/test_save.md`           |
| `test/commands/save_test.dart`        | `.claude/commands/test_save.md`           |
| `lib/commands/launch.dart`            | `.claude/commands/test_launch.md`         |
| `test/commands/launch_test.dart`      | `.claude/commands/test_launch.md`         |
| `lib/commands/link.dart`              | `.claude/commands/test_link.md`           |
| `test/commands/link_test.dart`        | `.claude/commands/test_link.md`           |
| `lib/commands/preflight_cmd.dart`     | `.claude/commands/test_preflight.md`      |
| `test/commands/preflight_cmd_test.dart` | `.claude/commands/test_preflight.md`    |
| `lib/commands/kill.dart`              | `.claude/commands/test_commands.md`       |
| `test/commands/kill_test.dart`        | `.claude/commands/test_commands.md`       |
| `lib/commands/status.dart`            | `.claude/commands/test_commands.md`       |
| `test/commands/status_test.dart`      | `.claude/commands/test_commands.md`       |
| `lib/session/session_state.dart`      | `.claude/commands/test_session.md`        |
| `test/session/session_state_test.dart` | `.claude/commands/test_session.md`       |
| `lib/file_io.dart`                    | all feature files (read each in sequence) |
| `test/helpers/`                       | all feature files (read each in sequence) |

How to execute a feature test file inline:
1. Read the file at the path shown above.
2. Run the `dart test` command from its **Step 1**.
3. If tests fail — stop. Do not proceed to the full suite.
4. Check every rule in its **Step 2** against the current code.
5. Report any violations. Stop if any rule is violated.

"All feature files" means read and execute all seven in sequence:
`.claude/commands/test_session.md`, `test_registry.md`, `test_save.md`,
`test_launch.md`, `test_link.md`, `test_commands.md`, `test_readme.md`.

---

## Step 2 — Full suite with random seed

```
CLAUDART_WORKSPACE=/tmp/claudart_test dart test --test-randomize-ordering-seed=random --reporter=expanded
```

Record the seed. If any test fails:
- Report: seed, test name, file, failure message
- Do not proceed to rule checks
- Tell the user: re-run with `--test-randomize-ordering-seed=<seed>` to reproduce

---

## Step 3 — Global rules (checked after full suite passes)

These rules span all modules. They are checked here, not in feature files.

### FileIO abstraction
No `lib/` file except `file_io.dart` and `process_runner.dart` may use
raw `dart:io` for file reads or writes.
```
grep -rn "File(\|Directory(\|Link(" lib/ --include="*.dart" \
  | grep -v "file_io.dart\|process_runner.dart"
```
Any result is a violation.

### Guard coverage
Every command that mutates workspace state calls `withGuard`.
```
grep -rn "writeFile\|fileIO.write\|io.write" lib/commands/ --include="*.dart"
```
Any write outside a `withGuard` call is a violation.

### No circular imports in session/
`session_ops.dart` must not import `workspace_guard.dart`.
`workspace_guard.dart` must not import `session_ops.dart`.
```
grep -n "workspace_guard" lib/session/session_ops.dart
grep -n "session_ops" lib/session/workspace_guard.dart
```
Any result is a violation.

### No dc-flutter context in this repo
```
bash test/claude_md_test.sh
```
All 7 checks must pass.

### Randomization is always used
The `/test` command always passes `--test-randomize-ordering-seed=random`.
Tests must never be run without it during development.
Hard-coded seeds are only acceptable for reproducing a specific failure.

---

## Step 4 — Promotion check (skills → rules)

Read `.claude/commands/` — scan all feature test files for coverage gaps
marked with `—` in their coverage tables.

Also read `skills.md` in the active workspace (if it exists).
Check if any `## Pending` entry describes a pattern that has appeared in 2+
sessions. If so, flag it for promotion into the relevant feature test file:

> "Pattern X has appeared in N sessions — consider adding it as a rule
> to test_session.md / test_registry.md."

This is how the test suite learns. Skills.md Pending is the incubator.
Feature test files are the enforcement layer.

---

## Step 5 — Final report

```
claudart /test
  Seed    : <seed>
  Passed  : <n> / <n>
  Failed  : 0

Feature rules
  ✓ test_session   (workspace_guard + session_ops)
  ✓ test_registry  (registry)
  ✓ test_save      (save + knowledge chain)
  ✓ test_launch    (launcher)
  ✓ test_link      (link + registry integration)
  ✓ test_commands  (kill + session_state)
  ✓ test_readme    (README glossary + architecture + command routing)

Global rules
  ✓ FileIO abstraction
  ✓ Guard coverage
  ✓ No circular imports
  ✓ No dc-flutter context
  ✓ Randomization enforced

Promotion candidates from skills.md
  none

Safe to commit.
```

If anything fails, list violations with file + line.
Do not say "safe to commit" until all checks pass.
