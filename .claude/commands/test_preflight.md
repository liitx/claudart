# /test_preflight — preflight command test and rule checker

## Module context

**Owns:** `lib/commands/preflight_cmd.dart`,
`test/commands/preflight_cmd_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_preflight` directly for focused preflight testing.

---

Scope: `lib/commands/preflight_cmd.dart`, `test/commands/preflight_cmd_test.dart`
Run when: any change to `preflight_cmd.dart` or `preflight_cmd_test.dart`.

---

## Step 1 — Run scoped tests

```
CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/commands/preflight_cmd_test.dart \
  --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### preflight_cmd.dart

**Rule: preflight_cmd is IO-only glue — no business logic.**
All sync check logic lives in `sync_check.dart`. `preflight_cmd.dart` reads
files, calls `runPreflight`, and prints results. It must not re-implement any
check that belongs in `sync_check.dart`.

**Rule: Exit 0 for clean and warnings — exit 1 for errors only.**
Warnings are informational. They must never block the workflow.
> Check: `grep -n "exit_(1)" lib/commands/preflight_cmd.dart` — only one call site
> (when `result.hasErrors` is true, or when registry/git lookup fails)

**Rule: `exit` is injectable — never called as bare `exit()` inside `runPreflightCmd`.**
Bare `exit()` terminates the test process. All exit points must use the injected
`exitFn` so tests can assert on exit-path behaviour.
> Check: `grep -n "exit(" lib/commands/preflight_cmd.dart | grep -v "exit_("` → no results

**Rule: preflight_cmd uses registry — not legacy path getters.**
Project root → registry lookup → workspace path. No hardcoded paths from
`paths.dart` legacy getters.
> Check: `grep -n "handoffPath\b\|skillsPath\b" lib/commands/preflight_cmd.dart` → no results

**Rule: Missing files are handled gracefully — not treated as errors.**
If handoff.md or skills.md are missing, preflight reads them as empty strings
and passes them to `runPreflight`. It must not exit early or throw on missing files.

---

## Step 3 — Coverage check

| Scenario                                                    | Covered |
|-------------------------------------------------------------|---------|
| Registry miss — exits 1                                     | ✓       |
| Clean result — prints clean message, exits 0               | ✓       |
| Warning result — prints issues, exits 0                     | ✓       |
| Error result — prints issues, exits 1                       | ✓       |
| Missing handoff file — treated as empty, no crash          | ✓       |
| Missing skills file — treated as empty, no crash           | ✓       |
| test op: loads coverage files from commands dir            | ✓       |
| non-test op: ignores coverage files                         | ✓       |
| Missing commands dir — no crash                             | ✓       |

Flag any gap before marking this module clean.

---

## Step 4 — Report

```
Preflight module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  preflight_cmd rules : ✓ / ✗
  Coverage gaps       : none / <list>
```
