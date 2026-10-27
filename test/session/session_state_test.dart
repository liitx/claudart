import 'package:test/test.dart';
import 'package:claudart/session/debug_disposition.dart';
import 'package:claudart/session/handoff_finding.dart';
import 'package:claudart/session/handoff_section.dart';
import 'package:claudart/session/knowledge_transfer.dart';
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

/// Independent literals: what each status tells the owner to do next.
const _nextStep = <HandoffStatus, String>{
  HandoffStatus.suggestInvestigating: 'Run /suggest in your editor.',
  HandoffStatus.readyForSuggest:
      'Run /suggest in your editor to begin a new cycle.',
  HandoffStatus.readyForDebug: 'Run /debug in your editor.',
  HandoffStatus.debugInProgress:
      'Continue with /debug, or run /suggest if you hit a wall.',
  HandoffStatus.debugComplete: 'Verify with dart test, then claudart teardown '
      'to keep what was learned, or claudart rotate for the next issue.',
  HandoffStatus.needsSuggest:
      'Run /suggest in your editor — debug has a question for you.',
  HandoffStatus.noHandoff: 'Run: claudart setup',
  HandoffStatus.unknown: 'Run: claudart setup',
};

/// Only a finished fix has something to lose by `kill`.
const _killWarning = <HandoffStatus, String?>{
  HandoffStatus.suggestInvestigating: null,
  HandoffStatus.readyForSuggest: null,
  HandoffStatus.readyForDebug: null,
  HandoffStatus.debugInProgress: null,
  HandoffStatus.debugComplete: 'The fix is applied. kill does not update '
      'skills.md, so nothing from this session is learned; claudart teardown '
      'keeps it.',
  HandoffStatus.needsSuggest: null,
  HandoffStatus.noHandoff: null,
  HandoffStatus.unknown: null,
};

/// Independent literals: what knowledge transfer each status stands for.
const _expectation = <HandoffStatus, KnowledgeTransferExpectation>{
  HandoffStatus.suggestInvestigating: KnowledgeTransferExpectation.unconverged,
  HandoffStatus.readyForSuggest: KnowledgeTransferExpectation.converged,
  HandoffStatus.readyForDebug: KnowledgeTransferExpectation.converged,
  HandoffStatus.debugInProgress: KnowledgeTransferExpectation.converged,
  HandoffStatus.debugComplete: KnowledgeTransferExpectation.converged,
  HandoffStatus.needsSuggest: KnowledgeTransferExpectation.none,
  HandoffStatus.noHandoff: KnowledgeTransferExpectation.none,
  HandoffStatus.unknown: KnowledgeTransferExpectation.none,
};

void main() {
  group('$HandoffStatus.knowledgeTransferExpectation', () {
    test('every status has a pinned expectation', () {
      expect(_expectation.keys.toSet(), HandoffStatus.values.toSet());
    });

    for (final status in HandoffStatus.values) {
      test('${status.name}: ${_expectation[status]!.name}', () {
        expect(status.knowledgeTransferExpectation, _expectation[status]);
      });
    }
  });

  group('$SessionState.findings', () {
    // Independent literals: a status that expects a transfer, against what the
    // handoff actually holds.
    const converged = KnowledgeTransfer.converged;
    const unconverged = KnowledgeTransfer.unconverged;
    HandoffFinding? expected(HandoffStatus status, KnowledgeTransfer held) =>
        switch ((_expectation[status]!, held)) {
          (KnowledgeTransferExpectation.converged, unconverged) =>
            HandoffFinding.statusAheadOfContent,
          (KnowledgeTransferExpectation.unconverged, converged) =>
            HandoffFinding.contentAheadOfStatus,
          (KnowledgeTransferExpectation.converged, converged) ||
          (KnowledgeTransferExpectation.unconverged, unconverged) ||
          (KnowledgeTransferExpectation.none, converged) ||
          (KnowledgeTransferExpectation.none, unconverged) =>
            null,
        };

    SessionState held(HandoffStatus status, KnowledgeTransfer transfer) =>
        SessionState(
          status: status,
          branch: 'main',
          bug: const HandoffSection('a real bug'),
          rootCause: HandoffSection(
            transfer == converged ? 'a cause' : '_Not yet determined._',
          ),
          scope: HandoffSection(
            transfer == converged ? 'lib/a.dart' : '_Not yet determined._',
          ),
          attempted: const HandoffSection('_Nothing yet._'),
          changed: const HandoffSection('_Nothing yet._'),
          unresolved: const HandoffSection('_Nothing yet._'),
        );

    for (final status in HandoffStatus.values) {
      for (final transfer in KnowledgeTransfer.values) {
        test('${status.name} holding ${transfer.name}', () {
          final finding = expected(status, transfer);
          expect(
            held(status, transfer).findings,
            finding == null ? isEmpty : [finding],
          );
        });
      }
    }
  });

  group('$SessionState debug disposition', () {
    String withDisposition(String handoff, String? value) => value == null
        ? handoff
        : '$handoff\n## Debug Disposition\n\n$value\n';

    test('a recorded disposition is read from the handoff', () {
      final state =
          SessionState.parse(withDisposition(_activeHandoff, 'skipped'));
      expect(state.recordedDebugDisposition, DebugDisposition.skipped);
      expect(state.debugDisposition, DebugDisposition.skipped);
    });

    test('a section followed by the handoff\'s rule is still read', () {
      final state = SessionState.parse(
        '$_activeHandoff\n## Debug Disposition\n\ndone\n\n---\n',
      );
      expect(state.recordedDebugDisposition, DebugDisposition.done);
    });

    test('with none recorded, a finished fix is done', () {
      final state = SessionState.parse(
        _activeHandoff.replaceFirst('ready-for-debug', 'debug-complete'),
      );
      expect(state.recordedDebugDisposition, isNull);
      expect(state.debugDisposition, DebugDisposition.done);
    });

    test('with none recorded, anything else is pending', () {
      final state = SessionState.parse(_activeHandoff);
      expect(state.recordedDebugDisposition, isNull);
      expect(state.debugDisposition, DebugDisposition.pending);
    });

    test('an unrecognised value is not recorded, so it is not guessed', () {
      final state =
          SessionState.parse(withDisposition(_activeHandoff, 'maybe later'));
      expect(state.recordedDebugDisposition, isNull);
    });
  });

  group('$SessionState.findings for the debug disposition', () {
    SessionState held(HandoffStatus status, DebugDisposition? recorded) =>
        SessionState(
          status: status,
          branch: 'main',
          bug: const HandoffSection('a real bug'),
          rootCause: const HandoffSection('a cause'),
          scope: const HandoffSection('lib/a.dart'),
          attempted: const HandoffSection('_Nothing yet._'),
          changed: const HandoffSection('_Nothing yet._'),
          unresolved: const HandoffSection('_Nothing yet._'),
          recordedDebugDisposition: recorded,
        );

    // Independent literals: only a finished fix is `done`, and a finished fix
    // is nothing else.
    bool disagrees(HandoffStatus status, DebugDisposition recorded) =>
        (status == HandoffStatus.debugComplete) !=
        (recorded == DebugDisposition.done);

    for (final status in HandoffStatus.values.where((s) => s.isPersisted)) {
      for (final recorded in DebugDisposition.values) {
        test('${status.name} recorded ${recorded.name}', () {
          final findings = held(status, recorded)
              .findings
              .where((f) => f == HandoffFinding.debugDispositionDisagrees);
          expect(findings.isNotEmpty, disagrees(status, recorded));
        });
      }

      test('${status.name} with none recorded never disagrees', () {
        expect(
          held(status, null).findings,
          isNot(contains(HandoffFinding.debugDispositionDisagrees)),
        );
      });
    }
  });

  group('$SessionState.knowledgeTransfer', () {
    test('an active handoff with a root cause and a scope is converged', () {
      expect(
        SessionState.parse(_activeHandoff).knowledgeTransfer,
        KnowledgeTransfer.converged,
      );
    });

    test('a blank handoff is unconverged', () {
      expect(
        SessionState.parse(blankHandoff).knowledgeTransfer,
        KnowledgeTransfer.unconverged,
      );
    });
  });

  group('$HandoffStatus.nextStep', () {
    test('every status has a pinned next step', () {
      expect(_nextStep.keys.toSet(), HandoffStatus.values.toSet());
    });

    for (final status in HandoffStatus.values) {
      test('${status.name}: next step', () {
        expect(status.nextStep, _nextStep[status]);
      });
    }
  });

  group('$HandoffStatus.killWarning', () {
    test('every status has a pinned answer', () {
      expect(_killWarning.keys.toSet(), HandoffStatus.values.toSet());
    });

    for (final status in HandoffStatus.values) {
      test('${status.name}: kill warning', () {
        expect(status.killWarning, _killWarning[status]);
      });
    }
  });

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
      expect(state.bug.text, contains('Config not loaded'));
    });

    test('reads rootCause', () {
      expect(state.rootCause.text, contains('ConfigLoader'));
    });

    test('reads attempted', () {
      expect(state.attempted.text, contains('Traced call'));
    });

    test('reads changed', () {
      expect(state.changed.text, contains('loader.dart'));
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
      expect(state.bug.isBlank, isTrue);
    });

    test('rootCause is placeholder', () {
      expect(state.rootCause.isBlank, isTrue);
    });

    test('attempted is placeholder', () {
      expect(state.attempted.text, startsWith('_Nothing'));
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
          bug: HandoffSection(bug),
          rootCause: HandoffSection(rootCause),
          scope: const HandoffSection('_Not yet determined._'),
          attempted: HandoffSection(attempted),
          changed: HandoffSection(changed),
          unresolved: HandoffSection(unresolved),
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

  group('SessionState.effectiveStatus', () {
    // What a consumer should show: a handoff with no real content is not a
    // session, whatever its Status line says (the blank handoff left by kill,
    // teardown and an empty rotate reads suggest-investigating).
    const blank = '_Not yet determined._';
    SessionState state(HandoffStatus status, {required bool active}) =>
        SessionState(
          status: status,
          branch: 'main',
          bug: HandoffSection(active ? 'Crash on save' : blank),
          rootCause: const HandoffSection(blank),
          scope: const HandoffSection(blank),
          attempted: const HandoffSection(blank),
          changed: const HandoffSection(blank),
          unresolved: const HandoffSection(blank),
        );

    for (final status in HandoffStatus.values) {
      test('${status.name}: active content keeps its own status', () {
        expect(state(status, active: true).effectiveStatus, status);
      });

      test('${status.name}: no active content is noHandoff', () {
        expect(
          state(status, active: false).effectiveStatus,
          HandoffStatus.noHandoff,
        );
      });
    }

    test('an empty file parses to noHandoff', () {
      expect(SessionState.parse('').effectiveStatus, HandoffStatus.noHandoff);
    });

    test('the blank handoff template parses to noHandoff', () {
      expect(
        SessionState.parse(blankHandoff).effectiveStatus,
        HandoffStatus.noHandoff,
      );
    });

    test('a handoff setup just wrote keeps suggestInvestigating', () {
      final written = handoffTemplate(
        branch: 'fix/x',
        date: '2026-01-01',
        bug: 'Real bug',
        expected: 'It works',
        projectName: 'my-app',
      );
      expect(
        SessionState.parse(written).effectiveStatus,
        HandoffStatus.suggestInvestigating,
      );
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
