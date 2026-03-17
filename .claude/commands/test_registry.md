# /test_registry — registry module test and rule checker

## Module context

**Owns:** `lib/registry.dart`, `lib/paths.dart`, `test/registry_test.dart`

**Invoked by:** `/test` reads this file inline when any owned file changes.

**Standalone:** Run `/test_registry` directly for focused registry module testing.

---

Scope: `lib/registry.dart`, `test/registry_test.dart`
Run when: any change to `registry.dart`, `paths.dart`, or `registry_test.dart`.

---

## Step 1 — Run scoped tests

```
dart test test/registry_test.dart --test-randomize-ordering-seed=random --reporter=expanded
```

Record seed and result. Stop if any test fails.

---

## Step 2 — Module rules

### Registry data structure

**Rule: Registry is backed by `Map<String, RegistryEntry>` internally.**
`findByName`, `add`, `remove`, `touchSession` must all be O(1).
No `for` loop over entries for name-keyed operations.
> Check: `grep -n "for.*entries\|for.*_byName" lib/registry.dart`
> Only `findByProjectRoot` and serialisation loops are acceptable.

**Rule: `findByProjectRoot` is the only permitted O(n) scan.**
It scans because `projectRoot` is a non-key value — no structure eliminates
this. All other lookups must use the map.

**Rule: Registry operations are immutable.**
`add`, `remove`, `touchSession` return new `Registry` instances.
They must never mutate `_byName` of the receiver.
> Verified by: `does not mutate original registry`

**Rule: `_warning` field is always written on save.**
Every `registry.json` written by `Registry.save()` must contain the
`_warning` key. This protects users from manual edits.
> Verified by: `writes _warning field`

### Registry as source of truth

**Rule: Registry is the only index of known projects.**
No command discovers projects by scanning the filesystem.
All project knowledge flows through `Registry.load()` → `Registry.findByName()`
or `Registry.findByProjectRoot()`.

**Rule: `lastSession` is updated via `touchSession` only.**
No command writes `lastSession` directly to `registry.json`.
`touchSession` is the single mutation point for session timestamps.

**Rule: `sensitivityMode` in the registry mirrors `config.json`.**
When sensitivity mode changes, both registry entry and workspace `config.json`
must be updated in the same operation. Never update one without the other.

---

## Step 3 — Coverage check

| Scenario                              | Covered |
|---------------------------------------|---------|
| Load — file missing                   | ✓       |
| Load — file corrupt                   | ✓       |
| Load — sensitivityMode missing in json| ✓       |
| Save — _warning present               | ✓       |
| Round-trip single entry               | ✓       |
| Round-trip multiple entries           | ✓       |
| findByName — found                    | ✓       |
| findByName — not found                | ✓       |
| findByProjectRoot — found             | ✓       |
| findByProjectRoot — not found         | ✓       |
| add — new entry                       | ✓       |
| add — replace existing (no growth)    | ✓       |
| add — immutability                    | ✓       |
| remove — exists                       | ✓       |
| remove — other entries unaffected     | ✓       |
| remove — safe when missing            | ✓       |
| touchSession — updates date           | ✓       |
| touchSession — other entries safe     | ✓       |
| touchSession — safe when missing      | ✓       |

Flag any gap before marking this module clean.

---

## Step 4 — Report

```
Registry module
  Seed    : <seed>
  Passed  : <n>
  Failed  : <n>

  Data structure rules  : ✓ / ✗
  Source of truth rules : ✓ / ✗
  Coverage gaps         : none / <list>
```
