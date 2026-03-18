# Experiment 03 — Type System Design Session

**Date:** 2026-03-18
**Branch:** main
**Model:** Claude Sonnet 4.6
**Goal:** Define the type system laws that govern when to use enum / Map / Set / extension.
**Secondary discovery:** Extensions on enums as the correct mechanism for test fixtures.

---

## The conversation that produced the laws

The session started from a question about whether `ScanScope` (`lib | full | handoff`)
should become an enum, and whether slash commands should be mapped from enums.

> "yes it should be a map that has an enum mapped to the exhaustive slash commands and
> i see you're missing /suggest in your question. so, that's what I'm talking about —
> we need to create skills for how entities are structured, how they pass data to update
> the json workspace. and then tests are improved with real intended data via extension
> on enum. also dart introduces enum functionalities inside the enum, we need to group
> features as much as possible to that tier of enums. and if we need to use two enums
> or more, we can create maps, and if something can never be repeated, we need to enforce
> sets, as a set only contains unique values. let's first start with code.md to enforce
> structure and decisions when to pivot to another datatype like map because I want
> performance, even matrix math.log — I want this to be inviting any math operation
> that's best used for functionality, while we're operating on it mathematically the
> output is still the respective type. does this make sense?"

Response that captured it:

> Yes — this makes complete sense. You're describing a type system design document that enforces:
> - Enums for finite known sets (with functionality inside the enum)
> - Maps when two enums have a relationship (EnumA → EnumB)
> - Sets when uniqueness must be enforced at the type level
> - Math operations on collections where applicable (log-scale similarity, cosine — already exists in cosine.dart)
> - Extensions on enums for test data (no hardcoded strings in tests, enum drives the fixture)

---

## The four laws

### Law 1 — Enum for finite sets

If the set of values is known at compile time, it is an enum.
Functionality belongs inside the enum: getters, methods, exhaustive switch.
No bare string literals where an enum can own the value.

```dart
// Wrong
String operation = 'debug';
switch (operation) {
  case 'debug': ...
  case 'save':  ...
}

// Right
enum ClaudartOperation {
  debug, save, test;
  bool get blocksOnError => this == debug;
}
```

### Law 2 — Map for enum relationships

When two enums have a relationship, the relationship is a `Map<EnumA, EnumB>`,
not a switch. The map is the data structure; the switch is a runtime reimplementation
of it.

```dart
// Wrong
String areaFor(TeardownCategory cat) => switch (cat) {
  TeardownCategory.apiIntegration => 'api',
  ...
};

// Right
const Map<TeardownCategory, String> _area = {
  TeardownCategory.apiIntegration: 'api',
  TeardownCategory.concurrency:    'async',
  ...
};
```

When the relationship is `EnumA → EnumB` (typed both sides), exhaustiveness
can be verified by checking `map.length == EnumA.values.length`.

### Law 3 — Set for uniqueness

When a collection must never contain duplicates, use `Set`, not `List`.
Prefer `const Set<T>` for lookup tables: O(1) membership, compiler-enforced
uniqueness, immutable.

```dart
// Wrong — List allows duplicates; linear search
final List<String> reserved = ['debug', 'save', 'test'];
if (reserved.contains(op)) ...

// Right — Set; O(1) lookup; duplicates impossible
const Set<String> _reserved = {'debug', 'save', 'test'};
if (_reserved.contains(op)) ...
```

### Law 4 — Math operations preserve type

Mathematical operations on collections return the same collection type.
While operating mathematically, the output is the respective Dart type.
Existing example: `cosine.dart` returns a `double` from two `List<double>` vectors.
This is correct — the math operation (cosine similarity) maps to its natural output type.

For similarity scoring: `math.log` for log-scale weighting is appropriate when
token frequency distributions are skewed. Apply it where the math is the best fit,
not as decoration.

### Law 5 — Extensions on enums for test fixtures

Test data is derived from enum variants, not hardcoded. An extension on the enum
generates the fixture. No bare strings in tests.

```dart
// Wrong
test('api integration teardown', () {
  final result = teardown('api-integration', ...);
  ...
});

// Right
extension TeardownCategoryFixture on TeardownCategory {
  String get fixture => '## Session\n\nCategory: $value\n';
}

test('api integration teardown', () {
  final result = teardown(TeardownCategory.apiIntegration, ...);
  expect(result, contains(TeardownCategory.apiIntegration.value));
});
```

---

## What goes in `code.md`

This is the reasoning contract for the mathematical/technical persona:

```
Type system laws — applied in this order:

1. Enum: if the set of values is finite and known at compile time, it is an enum.
   Functionality (getters, methods) lives inside the enum.
   No switch on a bare string where an enum can own it.

2. Map<EnumA, EnumB>: when two enums have a relationship, express it as a const Map.
   Verify exhaustiveness: map.length == EnumA.values.length.

3. const Set<T>: when uniqueness must be enforced. O(1) lookup. No List for membership tests.

4. Math operations: use log, cosine, dot product where they are the correct tool.
   Output type = the Dart type that best represents the result (double, int, List<double>).
   cosine.dart is the reference implementation.

5. Extensions on enums: test fixtures are derived from enum variants via an extension.
   No hardcoded strings in tests. The enum drives the fixture data.
```

---

## Context: where this came from

The design session (`experiments/2026-03-17-reasoning-design-session.md`) produced the
mathematical reasoning mode and the templates. This session (2026-03-18) made it explicit
as a type system law — starting from the observation that `ScanScope` should be an enum
and that slash commands (`/suggest`, `/debug`, `/save`, `/teardown`) should be exhaustively
mapped from that enum, not hardcoded as strings.

The insight: once you express the slash command set as an enum, you can:
- Map each variant to its file path (Map<ClaudartCommand, String>)
- Verify exhaustiveness at compile time (missing enum case = compile error)
- Use extensions to generate test fixtures without hardcoded strings
- Enforce `const Set<ClaudartCommand>` where duplicates must be impossible

---

## In-process state audit (same session)

**Question:** what kind of state does claudart need, and what shape should it take?

**Answer:** claudart is a short-lived CLI — runs, does file I/O, exits. It holds no
state across invocations. The question is: *what shape should in-process state take
during a single command run?*

| State | Current shape | Right shape | Why |
|---|---|---|---|
| Registry entries | `Map<String, RegistryEntry>` (JSON → map) | `HashMap<String, RegistryEntry>` | Lookup only, no ordering needed → O(1) |
| Handoff fields | Parsed via regex **each call site** | `HandoffState` record, parsed once | Avoids re-running 6+ regexes on the same string |
| Scan results | `List<String>` paths | `List<(String path, int tokens)>` record | Dart 3 records are value types — no class boilerplate |
| Ignore patterns | `List<String>` with `contains()` | `const Set<String>` | O(1) membership vs O(n) |
| `_testFileNames` | Probably List | `const Set<String>` | Same — uniqueness + O(1) |
| Hot path counts | Parsed from markdown each time | `Map<String, int>` built once | `putIfAbsent` O(1) update per file |
| Token map | `Map<String, int>` from JSON | Same, but `HashMap` | Unordered lookup |

**The real gain isn't any single collection — it's parse once, pass immutable.**
Right now `handoff.md` gets regex-parsed multiple times across a command.
A single `HandoffState` record passed through the call chain eliminates that:

```dart
// Dart 3 record — stack-allocated, destructurable, no class needed
typedef HandoffState = ({
  String branch,
  String bug,
  String rootCause,
  String debugProgress,
  HandoffStatus status,
});
```

Parse once at the command entry point. Pass the record. Every downstream
call site reads `state.branch` — O(1) field access, zero regex.

---

## Todos filed from this session

- [ ] `ScanScope` → enum (`lib`, `full`, `handoff`)
- [ ] Slash command set → `ClaudartCommand` enum mapped to file paths
- [ ] `code.md` template in `knowledge_templates.dart` — add type system laws section
- [ ] Enum extension pattern — add to `testing.md` as the fixture law
- [ ] `HandoffState` record — parse once at command entry, pass immutable through call chain
- [ ] `Registry` entries → `HashMap` (currently plain `Map` from JSON decode)
- [ ] Ignore patterns → `const Set<String>` (currently `List` with linear `contains`)
- [ ] `_testFileNames` in `preflight_cmd.dart` → `const Set<String>`
