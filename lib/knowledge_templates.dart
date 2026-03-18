// Generic starter content for workspace knowledge files.
// Updated by claudart teardown as sessions accumulate.

// ignore_for_file: prefer_single_quotes
const String codeTemplate = '''
# Code Design Principles
> Reasoning contract: table-first | theory → rule → example | enum-first | parse-once.
> Updated by claudart teardown. Do not edit manually.

---

## Enum-first law

**Theory:** An enum is a finite, typed set. Every string literal used in a switch,
comparison, or Map key is an untyped set element. Replacing it with an enum value makes
the set explicit, exhaustive, and compiler-verified.

**Rule:** No bare string literals where an enum can own the value.
Every `switch` on a `String` is an enum candidate. Every `Map<String, X>` with a
fixed key set is an enum candidate.

**Security:** In a self-hosted AI tool, bare strings are injection surfaces. The model
reading and optimizing its own source can introduce strings matching its own command
vocabulary. Enum values are compile-time constants — the compiler rejects injected
strings that don't match a declared variant.

```dart
// Bad — bare string, untyped, injectable
if (op == 'debug') { ... }

// Good — enum-owned, exhaustive, compile-time verified
switch (op) {
  case PreflightOp.debug: ...
  case PreflightOp.save: ...
  // compiler errors if a new variant is added without a handler
}
```

---

## Dart Enhanced Enums — capability table

| Feature | Syntax | When to use |
|---|---|---|
| Getter | `String get value => switch(this) { ... }` | Owned string/int value per variant |
| Method | `bool matches(String s) => value == s` | Behavior scoped to the enum |
| Exhaustive switch | `switch (e) { case A: ... }` | All variants handled, no default needed |
| When-guard | `case A when condition:` | Variant + extra condition in one branch |
| Record pair | `(TeardownCategory, String)` | Attach contextual data to a variant |
| Static factory | `static T fromString(String s)` | Parse external input to enum safely |
| `values` | `Enum.values` | Menus, test matrices, iteration |
| `name` | `e.name` | Debug display — no manual string needed |

---

## When to use enum vs sealed class vs record vs extension type

| Construct | Use when | Avoid when |
|---|---|---|
| `enum` | Fixed set of variants, each with owned values/behavior | Variants need different fields |
| `sealed class` | Variants need different fields (ADT / discriminated union) | Set is fixed and simple |
| `record` | Lightweight named tuple, no behavior, short-lived | You need methods or identity |
| `extension type` | Wrap a primitive with domain meaning, zero runtime cost | You need inheritance |

---

## Parse-once rule

**Theory:** Re-parsing the same source string at multiple call sites is O(n×k) cost
with no benefit — scattered failure modes and duplicate regex overhead.

**Rule:** Parse at the command entry point. Pass an immutable record down the call chain.
Never call a regex-based extractor more than once per command invocation.

```dart
// Bad — regex runs 3+ times on the same handoff string
final branch = extractBranch(handoff);
print(extractBranch(handoff));  // again

// Good — parse once, pass record, field access is O(1)
final state = parseHandoff(handoff);
print(state.branch);
```

---

## Three-layer explanation rule

When explaining or documenting any design decision:
1. **Theory** — why this is mathematically or architecturally correct
2. **Rule** — the enforceable constraint (lint, type, test gate)
3. **Example** — the concrete code that demonstrates it

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

String dartTemplate(String dartVersion) => '''
# Dart Practices
> Dart $dartVersion | Reasoning contract: see code.md.
> Updated by claudart teardown. Do not edit manually.

---

## Collection type decision table

| Need | Right type | Complexity |
|---|---|---|
| Lookup by key, no ordering needed | `HashMap<K, V>` | O(1) get/put |
| Lookup + insertion order preserved | `LinkedHashMap<K, V>` (default `{}`) | O(1) get/put |
| Lookup + sorted iteration | `SplayTreeMap<K, V>` | O(log n) get/put |
| Membership test, uniqueness enforced | `HashSet<T>` / `Set<T>` | O(1) contains |
| Sorted membership | `SplayTreeSet<T>` | O(log n) contains |
| Ordered, indexed sequence | `List<T>` | O(1) index, O(n) search |
| Immutable fixed lookup table | `const Set<T>` / `const <K,V>{}` | Compile-time |
| Lightweight named tuple, no behavior | Record `({T a, U b})` | Stack-allocated |

**Rule:** Start with `const Set` for lookup tables. Use `HashMap` when insertion order
does not matter. Only reach for `SplayTreeMap` when sorted output is required.

---

## Dart Enhanced Enums

Dart 2.17+ enums are sealed classes. Every enum can carry getters, methods,
`final` fields, static factories, and exhaustive switches.

When-guards collapse variant + condition into one branch:
```dart
switch (status) {
  case HandoffStatus.readyForDebug when hasCheckpoint: // variant + guard
    return startDebug();
  case HandoffStatus.readyForDebug:
    return promptCheckpoint();
  ...
}
```

**Enum test matrix rule:** `enum.values × getters` = required test cells.
Every variant × every getter must have an assertion. New variant = new row.
New getter = new column. Both require filling every cell before the session closes.

---

## When to use isolates

| Work type | Right choice | Why |
|---|---|---|
| I/O-bound (file, network, process) | `async/await` on main isolate | Offloads I/O, frees main thread |
| CPU-bound, one-shot (parse, hash, compress) | `Isolate.run()` | Offloads, auto-cleanup |
| CPU-bound, long-lived bidirectional | `Isolate.spawn()` + `SendPort` | Persistent channel |

**Rule:** Prefer `Isolate.run()` over `spawn()` unless you need a persistent `SendPort`.
Message types must be sendable — the analyzer does not catch non-sendable types
statically. This is a runtime error only.

**Isolate lint gap:** `cancel_subscriptions` catches unclosed `ReceivePort`. Sendable type
checking is unenforced statically — see analysis_options.yaml TODO for `custom_lint` plan.

---

## Sealed class vs enum

```dart
// Enum — all variants share structure, each owns values via getters
enum HandoffStatus {
  suggestInvestigating, readyForDebug, resolved;
  String get value => switch (this) { ... };
  static HandoffStatus fromString(String s) => ...;
}

// Sealed class — variants have different shapes (ADT)
sealed class ScanResult {}
final class ScanSuccess extends ScanResult {
  final List<ScanEntry> entries;
  ScanSuccess(this.entries);
}
final class ScanError extends ScanResult {
  final String message;
  ScanError(this.message);
}
```

---

## Records (Dart 3)

Anonymous, immutable, structural value types. Use for:
- Lightweight named tuples without behavior
- Returning multiple values from a function
- Short-lived local data structures

```dart
typedef HandoffState = ({
  String branch,
  String bug,
  String rootCause,
  HandoffStatus status,
});
```

---

## General rules

- `const` constructors wherever possible
- `late` is a smell — prefer nullable or required initialisation
- `dynamic` is banned — use generics or `Object?` with type checks
- Named parameters for functions with more than two arguments
- `extension` types to wrap primitives with domain meaning

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

const String testingTemplate = '''
# Testing Patterns
> Coverage model: T ⊇ C. Gap = T − C. Session done when gap = ∅.
> Updated by claudart teardown. Do not edit manually.

---

## When a test is required

A test must exist before a session closes when any of the following are true:
- A public function or method is added or changed
- An enum gains a variant, getter, or static factory
- A regex or parse rule is modified
- A new conditional branch is introduced
- A record type gains a field

---

## Coverage model

```
T = set of all testable behaviors
    (public functions + enum contracts + parse rules + branches)
C = set of behaviors with assertions
Gap = T − C
```

Every new public function adds an element to T.
Every new enum variant × getter adds a cell to the required matrix.
A session is complete when gap = ∅ — verified by running the full test suite.

---

## Enum test matrix rule

**Rule:** For every enum with getters: test matrix = `enum.values × getters`.
Every cell must have an assertion. No getter escapes coverage.

```dart
// Enum declares its own test matrix:
// 8 variants × 3 getters (.value, .area, .label) = 24 required assertions

test('each value matches expected string', () {
  expect(TeardownCategory.apiIntegration.value, 'api-integration');
  expect(TeardownCategory.concurrency.value,    'concurrency');
  // ... all variants
});
test('each area maps correctly', () {
  expect(TeardownCategory.apiIntegration.area, 'api');
  // ...
});
```

---

## Injectable interfaces — testability rule

No hardcoded stdin/stdout/File access in `lib/`. Every command function takes:

| Parameter | Type | Purpose |
|---|---|---|
| `io` | `FileIO?` | Injectable file system |
| `confirmFn` | `bool Function(String)?` | Injectable yes/no prompt |
| `promptFn` | `String? Function(String, {bool optional})?` | Injectable text input |
| `pickFn` | `int Function(List<String>)?` | Injectable menu selection |
| `exitFn` | `Never Function(int)?` | Injectable process exit |

This allows tests to run without a TTY, real file system, or process exit side effects.

---

## Test structure rules

- One assertion per test — one reason to fail
- Group by behavior, not by file: `group('extractBranch', () { ... })`
- Name tests in plain English: what the behavior is, not what code is called
- Fixture data: inline constants in the test file, not external files
- Randomized ordering is required: `dart test --test-randomize-ordering-seed=random`

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

String projectTemplate(String projectName) => '''
# Project: $projectName
> Updated by claudart teardown. Do not edit manually.

---

## Context

_Describe the project here. Updated as sessions accumulate._

---

## Architecture

_Key architectural decisions relevant to debugging._

---

## Hot paths

> Files confirmed useful across sessions. `↑` = confirmed once per session.

_Populated by teardown._

---

## Root cause patterns

> Patterns specific to this project.

_Populated by teardown._

---

## Anti-patterns

> Things that look relevant but aren't. Skip these first.

_Populated by teardown._
''';

String claudeMdTemplate({
  required String workspacePath,
  required String projectName,
  required List<String> genericFiles,
  String? sdkConstraint,
  String? flutterConstraint,
}) {
  final genericRefs = genericFiles
      .map((f) => '- $workspacePath/knowledge/generic/$f')
      .join('\n');

  final envLines = StringBuffer();
  if (sdkConstraint != null || flutterConstraint != null) {
    envLines.writeln('\n## Environment\n');
    if (sdkConstraint != null) envLines.writeln('- Dart SDK: `$sdkConstraint`');
    if (flutterConstraint != null) envLines.writeln('- Flutter: `$flutterConstraint`');
    envLines.writeln('\nDo not suggest APIs or syntax unavailable within these constraints.');
    envLines.writeln('\n---');
  }

  return '''
# CLAUDE.md
> Generated by claudart link | Project: $projectName
> Do not edit manually — re-run `claudart link` to regenerate.

## Workflow protocol

Always follow this order — no exceptions:
1. **Verify** — read the relevant files, understand current state
2. **Test** — run safely
3. **Confirm** — present result, wait for user confirmation
4. **Commit** — only after confirmed

Never commit before testing. Never skip confirmation.

---
$envLines
## Knowledge base

Read the following files at the start of every session before doing anything else.

### Generic practices
$genericRefs

### Project context
- $workspacePath/knowledge/projects/$projectName.md

### Session state
- $workspacePath/handoff.md
- $workspacePath/skills.md

---

## Git rules

- **Never push to remote** under any circumstances
- Local commits only, and only when explicitly requested
''';
}
