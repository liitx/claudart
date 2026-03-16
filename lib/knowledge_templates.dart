// Generic starter content for workspace knowledge files.
// Updated by claudart teardown as sessions accumulate.

String dartFlutterTemplate(String flutterVersion, String dartVersion) => '''
# Generic Dart / Flutter Practices
> Flutter $flutterVersion | Dart $dartVersion
> Updated by claudart teardown. Do not edit manually.

---

## Dart

- Prefer `const` constructors wherever possible
- Use `sealed` classes for exhaustive pattern matching over enums with behaviour
- Avoid `dynamic` — use generics or `Object?` with type checks
- Prefer named parameters for functions with more than two arguments
- Use `extension` types to wrap primitives with domain meaning
- `late` is a smell — prefer nullable or required initialisation

---

## Flutter

- Never import `material` or `cupertino` directly — use `flutter/widgets.dart`
- Prefer `const` widgets to minimise rebuild scope
- Widget build methods should contain zero logic — extract to methods or classes
- Use `Key` types (`ValueKey`, `ObjectKey`) deliberately; avoid random keys
- Avoid `setState` inside `initState` — use `WidgetsBinding.addPostFrameCallback`

---

## State management

See `bloc.md` and `riverpod.md` for pattern-specific guidance.

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

const String blocTemplate = '''
# BLoC Patterns
> Updated by claudart teardown. Do not edit manually.

---

## Events

- One event per user intent — do not reuse events for different triggers
- Events should be immutable (`final` fields, `const` constructors via `Equatable`)
- Avoid passing callbacks inside events

## State

- State should be a single sealed class with named subclasses
- Never emit the same state object twice — `Equatable` handles identity checks
- Keep state flat; avoid deeply nested state trees

## BLoC class

- Use `EventTransformer` from `bloc_concurrency` for concurrent/sequential control:
  - `sequential()` — one event at a time, queue the rest
  - `restartable()` — cancel previous, start new (search, debounce)
  - `droppable()` — ignore new events while one is in progress
- Keep BLoC methods private; only expose `add(event)`
- Never call `add()` from inside the BLoC — use `emit` chains

## Testing

- Test every `(state, event) → state` transition
- Use `blocTest` from `bloc_test` package
- Mock repositories with `mocktail`

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

const String riverpodTemplate = '''
# Riverpod Patterns
> Updated by claudart teardown. Do not edit manually.

---

## Providers

- Prefer `@riverpod` codegen over manual provider declarations
- Keep providers small and single-purpose
- Use `ref.watch` in build methods, `ref.read` in callbacks only
- Never use `ref.read` inside `build` — it won't rebuild on change

## AsyncNotifier

- Use `AsyncNotifier` for async state with loading/error/data
- Use `ref.invalidate` to force a refresh; avoid manual state resets

## Family providers

- Use `.family` for parameterised providers (e.g. by ID)
- Ensure family arguments implement `==` and `hashCode`

## Testing

- Use `ProviderContainer` with `overrides` in tests
- Use `riverpod_test` for `AsyncNotifier` testing

---

## Patterns to avoid

_Populated by teardown from real sessions._
''';

const String testingTemplate = '''
# Testing Patterns
> Updated by claudart teardown. Do not edit manually.

---

## Unit tests

- One assertion per test where possible — tests should have one reason to fail
- Name tests: `given_when_then` or plain English descriptions
- Mock at the boundary (repository level), not deep in the stack
- Use `mocktail` — prefer `when(...).thenReturn(...)` over manual fakes

## Widget tests

- Use `WidgetTester.pumpAndSettle` only when animations are involved
- Prefer `find.byType` over `find.byKey` — keys are implementation details
- Wrap widgets under test in `MaterialApp` only if routing is under test

## Golden tests

- Use `golden_toolkit` for layout regression
- Store goldens in `test/goldens/` — regenerate with `--update-goldens` flag

## Coverage

- 100% line coverage is required for critical packages in this repo
- Coverage gaps must be justified, not silently ignored

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

> Things that look relevant but aren\'t. Skip these first.

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
${envLines}
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
