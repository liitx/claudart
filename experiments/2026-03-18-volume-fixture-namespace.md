# Experiment — Volume/Pulse/Wave Fixture Namespace

**Date:** 2026-03-18
**Commits:** 309a044 (sweep), 7234e94 (renamed to Volume)
**Status:** Live on main

---

## What it is

A sweep across all test fixtures to replace domain-specific names with a
fictional audio-themed neutral namespace: **Volume / Pulse / Wave**.

The goal: zero association between claudart's test suite and any real project.
claudart is a generic Dart CLI — its tests should read that way.

---

## Why it matters

Before the rename, test fixtures leaked domain knowledge from the project claudart
was originally built alongside. After the rename, fixtures are clearly fictional:

```dart
// Before — tied to a real project's domain
'old_bloc.dart': 'class OldBloc extends Bloc<OldEvent, OldState> {}'
expect(result.entities.containsKey('OldBloc'), isTrue);
```

```dart
// After — neutral, audio-themed, no domain association
'volume_bloc.dart': 'class VolumeBloc extends Bloc<VolumeEvent, VolumeState> {}'
expect(result.entities.containsKey('VolumeBloc'), isTrue);

final v = tfidfVector('volume bloc', corpus);
'volume': 0.8, 'pulse': 0.9,
```

---

## Files affected

| File | What changed |
|---|---|
| `test/scanner/scanner_test.dart` | → VolumeBloc, VolumeRepository, VolumeWidget, VolumeStatus, VolumeCallback, VolumeBlocX |
| `test/similarity/cosine_test.dart` | corpus words → `'volume'`/`'pulse'`; tfidf variable → `volumeWeight` |
| `test/sensitivity/abstractor_test.dart` | Fixture tokens → Volume namespace |
| `test/sensitivity/detector_test.dart` | Fixture names → Volume/Pulse |
| `test/sensitivity/token_map_test.dart` | Token map fixtures → Volume namespace |
| `test/commands/scan_test.dart` | Fixture files → `volume_` prefix |
| `test/commands/map_test.dart` | Fixture content → Volume namespace |
| `test/logging/logger_test.dart` | Log fixture entries → Volume namespace |
| `test/ignore_rules_test.dart` | Ignore rule fixtures → Volume namespace |
| `lib/sensitivity/detector.dart` | Fixture string update |
| `test/teardown_utils_test.dart` | `incrementHotPath` area `'bloc'` → `'state'` (correctness fix — `'bloc'` was never a valid `TeardownCategory.area` value) |

---

## The `teardown_utils_test.dart` fix is separate

The `incrementHotPath` area change is a real correctness fix, independent of
the naming sweep:

```dart
// Before — not a real TeardownCategory.area value
incrementHotPath(skills, area: 'bloc', file: 'lib/state/notifier.dart');

// After — TeardownCategory.stateManagement.area
incrementHotPath(skills, area: 'state', file: 'lib/state/notifier.dart');
```

---

## Namespace convention

| Name | Role in fixtures |
|---|---|
| `Volume` | Primary entity — main class names, file prefixes |
| `Pulse` | Secondary entity — secondary corpus words, supporting types |
| `Wave` | Tertiary — three-entity fixture scenarios |

Audio-themed, fictional, zero association with any real project or client domain.
