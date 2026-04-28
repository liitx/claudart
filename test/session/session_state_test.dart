import 'package:test/test.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/handoff_template.dart';

// A fully-filled handoff as setup would produce it.
const _activeHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: fix/null-ref

---

## Status

ready-for-debug

---

## Bug

Config not loaded when path has spaces.

---

## Expected Behavior

Config loads regardless of spaces in path.

---

## Root Cause

ConfigLoader splits path on spaces before resolving.

---

## Scope

### Files in play
lib/config/loader.dart

### Key entry points in play
ConfigLoader

### Classes / methods in play
_Not yet determined._

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
Traced call through config loader — confirmed split.

### What changed (files modified)
lib/config/loader.dart — added path quoting.

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

void main() {
  group('SessionState.parse — active handoff', () {
    late SessionState state;

    setUp(() => state = SessionState.parse(_activeHandoff));

    test('reads status', () {
      expect(state.status, equals(HandoffStatus.readyForDebug));
    });

    test('reads branch', () {
      expect(state.branch, equals('fix/null-ref'));
    });

    test('reads bug', () {
      expect(state.bug, contains('Config not loaded'));
    });

    test('reads rootCause', () {
      expect(state.rootCause, contains('ConfigLoader'));
    });

    test('reads attempted', () {
      expect(state.attempted, contains('Traced call'));
    });

    test('reads changed', () {
      expect(state.changed, contains('loader.dart'));
    });

    test('hasActiveContent is true when real content present', () {
      expect(state.hasActiveContent, isTrue);
    });
  });

  group('SessionState.parse — blank handoff', () {
    late SessionState state;

    setUp(() => state = SessionState.parse(blankHandoff));

    test('status is suggest-investigating', () {
      expect(state.status, equals(HandoffStatus.suggestInvestigating));
    });

    test('branch is unknown (no branch line)', () {
      expect(state.branch, equals('unknown'));
    });

    test('bug is placeholder', () {
      expect(state.bug, startsWith('_Not'));
    });

    test('rootCause is placeholder', () {
      expect(state.rootCause, startsWith('_Not'));
    });

    test('attempted is placeholder', () {
      expect(state.attempted, startsWith('_Nothing'));
    });

    test('hasActiveContent is false for blank handoff', () {
      expect(state.hasActiveContent, isFalse);
    });
  });

  group('HandoffStatus round-trip — new variants', () {
    test('readyForSuggest round-trips via fromString / value', () {
      expect(HandoffStatus.fromString('ready-for-suggest'), equals(HandoffStatus.readyForSuggest));
      expect(HandoffStatus.readyForSuggest.value, equals('ready-for-suggest'));
    });

    test('debugComplete round-trips via fromString / value', () {
      expect(HandoffStatus.fromString('debug-complete'), equals(HandoffStatus.debugComplete));
      expect(HandoffStatus.debugComplete.value, equals('debug-complete'));
    });

    test('readyForSuggest expectsSuggest is true', () {
      expect(HandoffStatus.readyForSuggest.expectsSuggest, isTrue);
      expect(HandoffStatus.readyForSuggest.expectsDebug, isFalse);
    });

    test('debugComplete expects neither', () {
      expect(HandoffStatus.debugComplete.expectsSuggest, isFalse);
      expect(HandoffStatus.debugComplete.expectsDebug, isFalse);
    });
  });

  group('SessionState.parse — edge cases', () {
    test('empty string returns all empty/unknown', () {
      final state = SessionState.parse('');
      expect(state.status, equals(HandoffStatus.unknown));
      expect(state.branch, equals('unknown'));
      expect(state.hasActiveContent, isFalse);
    });

    test('branch with slash is preserved', () {
      const h = '> Session started: 2026-01-01 | Branch: feat/some-feature\n';
      final state = SessionState.parse(h);
      expect(state.branch, equals('feat/some-feature'));
    });

    test('branch trimmed of trailing whitespace', () {
      const h = '> Session started: 2026-01-01 | Branch: main  \n';
      final state = SessionState.parse(h);
      expect(state.branch, equals('main'));
    });
  });
}
