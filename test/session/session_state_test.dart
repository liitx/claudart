import 'package:test/test.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/handoff_template.dart';

// A fully-filled handoff as setup would produce it.
const _activeHandoff = '''# Agent Handoff — dc-flutter

> Session started: 2026-03-16 | Branch: feat/audio

---

## Status

ready-for-debug

---

## Bug

Audio stops after source switch.

---

## Expected Behavior

Audio continues seamlessly.

---

## Root Cause

StateNotifier holds stale reference after hot-reload.

---

## Scope

### Files in play
lib/audio/audio_bloc.dart

### BLoCs / providers in play
AudioBloc

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
Traced event through BLoC — confirmed stale ref.

### What changed (files modified)
lib/audio/audio_bloc.dart — added null guard.

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
      expect(state.branch, equals('feat/audio'));
    });

    test('reads bug', () {
      expect(state.bug, contains('Audio stops'));
    });

    test('reads rootCause', () {
      expect(state.rootCause, contains('StateNotifier'));
    });

    test('reads attempted', () {
      expect(state.attempted, contains('Traced event'));
    });

    test('reads changed', () {
      expect(state.changed, contains('audio_bloc.dart'));
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
