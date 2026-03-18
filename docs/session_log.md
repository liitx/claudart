# claudart — Session Log

> Running record of design decisions, cleanups, and known issues.
> Updated manually at the end of each significant work session.

---

## 2026-03-18 — Audit: enum-first enforcement, matrix completion, test depth, dc-flutter purge

### What this session did

**Full compliance audit against the laws captured in the design session experiment.**
The reasoning mode was working. The tests were not yet verifying it. That gap is closed.

### Enforcement work

**`ClaudartOperation` enum — enum-first law applied to `sync_check.dart`:**

`checkHandoffStatus` previously accepted a bare `String` and switched on
`'debug'` / `'save'` / `'test'` literals. Replaced with an exhaustive enum:

```dart
enum ClaudartOperation {
  debug, save, test;
  static ClaudartOperation fromString(String s) => switch (s) {
    'debug' => debug,
    'save'  => save,
    _       => test,
  };
}
```

Parse-once at boundary: `preflight_cmd.dart` calls `fromString` once on the CLI
arg; the enum passes through the entire call chain. No bare string comparisons
inside the library.

**Typed catches — `session_ops.dart`:**

Three `closeSession` rollback steps had bare `catch (e)`. Replaced with
`on Exception catch (e)`. Dart's typed catch rule: `Error` subclasses are
programmer mistakes that should propagate, not be swallowed.

**`TeardownCategory.label` — matrix completion:**

Enum test matrix M(E) = V × G. `TeardownCategory` has 8 variants × 3 getters
(`area`, `value`, `label`) = 24 required cells. The `label` getter was only
tested for `other` (1/8 cells). Added 7 missing assertions to complete the matrix.

**`incrementHotPath` area fix:**

Test used `'bloc'` as the area argument — not a real `TeardownCategory.area`
value. Changed to `'state'` (correct `stateManagement.area`).

### `knowledge_templates_test.dart` — mathematical content verification

The design session (`experiments/2026-03-17-reasoning-design-session.md`)
produced templates embedding formal math. Tests only checked heading presence —
the math itself was untested. Full rewrite:

| Template | What is now tested |
|---|---|
| `codeTemplate` | Theory/Rule/Example layer presence; O(n×k) parse-once proof; compile-time security rationale; enum capability table; enum-vs-sealed-vs-record-vs-extension-type table |
| `dartTemplate` | O(1)/O(log n) complexity in collection table; `const Set` lookup rule; `enum.values × getters` formula; isolate decision table; sealed class vs enum |
| `testingTemplate` | `T ⊇ C` set notation; `Gap = T − C`; `gap = ∅` session-done condition; `enum.values × getters`; `Every cell must have an assertion`; FileIO/confirmFn/exitFn injectable table; `randomize-ordering-seed` rule |
| `claudeMdTemplate` | Verify-before-commit workflow; `Never push to remote` git rule; `## Environment` section with SDK/Flutter constraints |

### dc-flutter contamination sweep

All `AudioBloc`, `VehicleBloc`, `media_ivi`, `dc-flutter`, `dc_flutter`
references removed from source, tests, READMEs, and git commit history.
Replaced with fictional Buster/Rover/Pilot namespace throughout test fixtures.
History rewrite: `git filter-branch` across all branches, `refs/original/`
deleted, gc run.

### Test count

| Session | Tests |
|---|---|
| 2026-03-17 | 375 |
| 2026-03-18 | 449 |

### Commits this session

```
5fdb1c6 test: expand knowledge_templates to verify mathematical content
9d2b4e5 fix: enum-first and matrix compliance
fe9f529 merge: refactor/audit — audit, Buster fixtures, rotate, typed catches, 413 tests
309a044 refactor: replace project-specific fixture names with Buster/Rover namespace
9b45855 refactor: audit — typed catches, falsifiable tests, setup coverage, generic fixture cleanup
```

---

## 2026-03-17 — Framework-agnostic cleanup + line editor + teardown improvements

### What claudart is

A generic Dart CLI that manages a structured suggest → debug → teardown workflow
for AI-assisted debugging sessions. It is not Flutter-specific. It runs on any
Dart project.

The workflow:

```
claudart link          — register project in workspace registry
claudart setup         — describe the bug; writes handoff.md
  ↓
/suggest               — AI explores the codebase, writes root cause to handoff
claudart save          — checkpoint confirmed root cause to skills.md (Pending)
  ↓
/debug                 — AI implements the fix, scoped to handoff
  ↓
claudart teardown      — classify session, archive handoff, update skills.md, suggest commit
```

### Commands (as of this session)

| Command               | What it does |
|-----------------------|--------------|
| `claudart`            | Interactive launcher — list projects, route into setup |
| `claudart init`       | Scaffold workspace: dart.md, testing.md, slash commands |
| `claudart init -p X`  | Add project knowledge file |
| `claudart link [name]`| Register project; write CLAUDE.md with workspace refs |
| `claudart unlink`     | Remove symlinks |
| `claudart setup`      | Prompt for bug context; write handoff.md |
| `claudart status`     | Show active session state; `--prompt` for shell RPROMPT |
| `claudart save`       | Snapshot handoff to archive/checkpoint_*; deposit root cause to skills.md Pending |
| `claudart teardown`   | Categorise session; archive handoff; update skills.md; suggest commit |
| `claudart kill`       | Abandon session without skills update |
| `claudart preflight`  | Sync check before debug/save/test |
| `claudart scan`       | Re-scan project for sensitive tokens |
| `claudart report`     | Diagnostic report |
| `claudart map`        | Generate token_map.md from token_map.json |
| `claudart experiment` | Run command and tee output to experiments/ |

### Files written by the workflow

```
~/.claudart/                        ← CLAUDART_WORKSPACE (global root, v2)
  registry.json                     ← maps project roots to workspace paths
  <project-name>/
    handoff.md                      ← live session state (suggest ↔ debug)
    skills.md                       ← accumulated cross-session learnings
    archive/
      checkpoint_<branch>_<ts>.md  ← save snapshots
      handoff_<branch>_<ts>.md     ← teardown archives
    knowledge/
      generic/
        dart.md                     ← generic Dart practices
        testing.md                  ← generic testing practices
      projects/
        <name>.md                   ← project-specific context
    commands/                       ← Claude Code slash commands
      suggest.md
      debug.md
      save.md
      teardown.md
    logs/
    token_map.json / token_map.md
```

### What was cleaned up this session

**Flutter/BLoC context removed from the generic CLI:**

Previously, claudart had hardcoded Flutter-specific assumptions throughout:
- `handoff_template.dart` had a `### BLoCs / providers in play` section
- `setup.dart` stored the answer in a `blocs` variable
- `teardown.dart` had Flutter-specific categories: `bloc-event-handling`,
  `widget-lifecycle`, `provider-state`, `ffi-bridge`
- `teardown_utils.dart` mapped categories to commit areas using BLoC/widget/ffi terms
- `suggest_template.dart` and `debug_template.dart` told the AI to read `bloc.md`
  and `riverpod.md` and traced `API → repository → BLoC/provider → widget`
- `knowledge_templates.dart` contained `blocTemplate` and `riverpodTemplate`
- `init.dart` wrote `bloc.md` and `riverpod.md` to the workspace on init

**Root cause:** These were claudart-specific assumptions carried over from the
original claudart workflow and never genericised.

**What replaced them:**
- Handoff section: `### Key entry points in play`
- Setup variable: `entryPoints`
- Teardown categories: `api-integration`, `concurrency`, `configuration`,
  `data-parsing`, `io-filesystem`, `state-management`, `general`, `other`
- `TeardownCategory` constants: `apiIntegration`, `concurrency`, `configuration`,
  `dataParsing`, `ioFilesystem`, `stateManagement`, `general`, `other`
- `areaFromCategory()`: maps to `api`, `async`, `config`, `io`, `state`, `data`, `fix`
- Knowledge starters: `dart.md` + `testing.md` only (no framework assumptions)
- Templates: generic data flow language; no framework-specific file references

**Note:** The scanner (`lib/scanner/`) and sensitivity modules (`lib/sensitivity/`)
still detect BLoC/Riverpod patterns — this is correct. Those modules scan
*target* project code, not claudart itself.

### Other improvements this session

- **Line editor** (`lib/ui/line_editor.dart`): raw-mode mini readline for all
  text prompts — left/right arrows, home/end, backspace, delete, Ctrl+A/E/U
- **Teardown pre-population**: hot files pre-filled from "What changed"; root
  cause pattern pre-filled from handoff Root Cause section
- **Arrow-key category menu**: teardown category selection uses `arrowMenu`
  instead of free-text entry
- **`TeardownCategory` named constants**: replaces magic indices in tests
- **Legacy path migration** (scan + logger): `scan.dart` and `logger.dart` now
  resolve paths per-project via `workspacePath` instead of the global `claudeDir`
- **21 unit tests** for teardown + **3 e2e smoke tests** (save → teardown pipeline)

### Known issues / open questions

1. **`setup` has no unit tests** — highest-priority coverage gap. Setup is the
   most complex command (prompts, handoff write, scan, logging) and has zero test
   coverage. Drift is likely here.

2. **`init` still detects Flutter version** — removed from template generation but
   `_detectVersion('flutter', ...)` call can be removed entirely since `claudeMdTemplate`
   accepts `flutterConstraint` as an optional param (used when target project is Flutter).

3. **skills.md Pending section** — the current `skills.md` in the self-hosted
   workspace has a malformed Pending entry (from a prior session where the category
   leaked). Review and clean manually if needed.

4. **`claudart scan` standalone** — resolves workspace from registry correctly now
   but has no dedicated test for the standalone binary path.

5. **Category selection is fixed-length** — if a user wants a project-specific
   category not in the list, they must pick `other (type manually)`. A future
   improvement: derive additional options from existing skills.md Root Cause Patterns.

### Test coverage summary

| Area                        | Tests |
|-----------------------------|-------|
| Registry                    | ✓     |
| HandoffTemplate             | ✓     |
| KnowledgeTemplates          | ✓     |
| TeardownUtils               | ✓     |
| SessionState                | ✓     |
| SyncCheck                   | ✓     |
| WorkspaceGuard              | ✓     |
| Link                        | ✓ 16  |
| Save                        | ✓     |
| Teardown                    | ✓ 21  |
| Kill                        | ✓     |
| Status                      | ✓     |
| Launch                      | ✓     |
| Preflight                   | ✓     |
| Scan                        | ✓     |
| E2E (save → teardown)       | ✓ 3   |
| **Setup**                   | ✗ 0   |
| README sync                 | ✓     |
| Total                       | 375   |

> **As of 2026-03-18:** 449 tests. See session entry above for what was added.

### Commit at end of session

```
ebcf12f fix: remove Flutter/BLoC context — claudart is framework-agnostic
```
