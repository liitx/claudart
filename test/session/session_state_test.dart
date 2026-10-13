import 'package:test/test.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart';

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

  group('HandoffStatus wire values', () {
    // Independent literal table: the on-disk contract, not derived from
    // the enum.
    const wire = {
      HandoffStatus.suggestInvestigating: 'suggest-investigating',
      HandoffStatus.readyForSuggest: 'ready-for-suggest',
      HandoffStatus.readyForDebug: 'ready-for-debug',
      HandoffStatus.debugInProgress: 'debug-in-progress',
      HandoffStatus.debugComplete: 'debug-complete',
      HandoffStatus.needsSuggest: 'needs-suggest',
      HandoffStatus.noHandoff: 'no-handoff',
      HandoffStatus.unknown: 'unknown',
    };

    test('the table covers every variant', () {
      expect(wire.keys.toSet(), HandoffStatus.values.toSet());
    });

    for (final entry in wire.entries) {
      test('${entry.key.name}: value is "${entry.value}"', () {
        expect(entry.key.value, entry.value);
      });
    }

    for (final entry in wire.entries.where((e) => e.key.isPersisted)) {
      test('${entry.key.name}: fromString("${entry.value}") parses back', () {
        expect(HandoffStatus.fromString(entry.value), entry.key);
      });
    }
  });

  group('HandoffStatus.expectsSuggest / expectsDebug', () {
    // Independent literal sets, the workflow gating zedup's tests also pin.
    const expectSuggest = {
      HandoffStatus.suggestInvestigating,
      HandoffStatus.readyForSuggest,
      HandoffStatus.needsSuggest,
      HandoffStatus.noHandoff,
      HandoffStatus.unknown,
    };
    const expectDebug = {
      HandoffStatus.readyForDebug,
      HandoffStatus.debugInProgress,
    };

    for (final status in HandoffStatus.values) {
      test('${status.name}: expectsSuggest is '
          '${expectSuggest.contains(status)}', () {
        expect(status.expectsSuggest, expectSuggest.contains(status));
      });

      test('${status.name}: expectsDebug is ${expectDebug.contains(status)}',
          () {
        expect(status.expectsDebug, expectDebug.contains(status));
      });

      test('${status.name}: never expects both', () {
        expect(status.expectsSuggest && status.expectsDebug, isFalse);
      });
    }
  });

  group('HandoffStatus.canStartDebug / isPersisted', () {
    const startsDebug = {
      HandoffStatus.readyForDebug,
      HandoffStatus.debugInProgress,
    };
    const displayOnly = {HandoffStatus.noHandoff, HandoffStatus.unknown};

    for (final status in HandoffStatus.values) {
      final starts = startsDebug.contains(status);
      final persisted = !displayOnly.contains(status);

      test('${status.name}: canStartDebug is $starts', () {
        expect(status.canStartDebug, starts);
      });

      test('${status.name}: isPersisted is $persisted', () {
        expect(status.isPersisted, persisted);
      });
    }
  });

  group('SessionState.hasActiveContent — each field alone', () {
    const blank = '_Not yet determined._';
    SessionState state({
      String bug = blank,
      String rootCause = blank,
      String attempted = blank,
      String changed = blank,
      String unresolved = blank,
    }) =>
        SessionState(
          status: HandoffStatus.suggestInvestigating,
          branch: 'main',
          bug: bug,
          rootCause: rootCause,
          attempted: attempted,
          changed: changed,
          unresolved: unresolved,
        );

    test('a real bug alone is active', () {
      expect(state(bug: 'Crash on save').hasActiveContent, isTrue);
    });

    test('a real root cause alone is active', () {
      expect(state(rootCause: 'Null guard missing').hasActiveContent, isTrue);
    });

    test('real attempted work alone is active', () {
      expect(state(attempted: 'Added a guard').hasActiveContent, isTrue);
    });

    test('changed files and an unresolved question alone are not', () {
      expect(
        state(changed: 'lib/a.dart', unresolved: 'Why?').hasActiveContent,
        isFalse,
      );
    });

    test('all placeholders is not active', () {
      expect(state().hasActiveContent, isFalse);
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
