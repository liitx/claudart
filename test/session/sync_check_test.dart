import 'package:test/test.dart';
import 'package:claudart/session/sync_check.dart';

// ── Shared handoff fixtures ───────────────────────────────────────────────────

const _branch = 'fix/null-ref';

String _handoff({
  String status = 'ready-for-debug',
  String rootCause = 'ConfigLoader splits path on spaces.',
  String bug = 'Config not loaded when path has spaces.',
}) => '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: $_branch

---

## Status

$status

---

## Bug

$bug

---

## Expected Behavior

Config loads regardless of spaces in path.

---

## Root Cause

$rootCause

---

## Scope

### Files in play
_Not yet determined._

### Key entry points in play
_Not yet determined._

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
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

const _blankHandoff = '''# Agent Handoff

> Source of truth between suggest and debug agents.

---

## Status

suggest-investigating

---

## Bug

_Not yet determined._

---

## Expected Behavior

_Not yet determined._

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### Key entry points in play
_Not yet determined._

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
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

// ── Shared skills fixtures ────────────────────────────────────────────────────

String _skillsWithPending(String branch) => '''# Accumulated Skills

---

## Pending

> Confirmed facts from in-progress sessions.

- `$branch` (2026-03-16): root cause — ConfigLoader splits path on spaces.

---

## Hot Paths

_No sessions recorded yet._
''';

const _skillsNoPending = '''# Accumulated Skills

---

## Pending

_Nothing yet._

---

## Hot Paths

_No sessions recorded yet._
''';

// ── Shared test file fixtures ─────────────────────────────────────────────────

const _testFileAllCovered = '''
| Scenario                   | Covered |
|----------------------------|---------|
| Happy path                 | ✓       |
| Empty state                | ✓       |
| Rollback on failure        | ✓       |
''';

const _testFileWithGaps = '''
| Scenario                   | Covered |
|----------------------------|---------|
| Happy path                 | ✓       |
| Empty state                | —       |
| Rollback on failure        | —       |
''';

const _testFileMixed = '''
| Scenario                   | Covered |
|----------------------------|---------|
| Happy path                 | ✓       |
| Edge case X                | —       |
| Rollback on failure        | ✓       |
''';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── checkSkillsSync ────────────────────────────────────────────────────────

  group('checkSkillsSync — confirmed root cause', () {
    test('clean when pending entry exists for branch', () {
      final result = checkSkillsSync(
        _handoff(),
        _skillsWithPending(_branch),
      );
      expect(result.isClean, isTrue);
    });

    test('warning when no pending entry for branch', () {
      final result = checkSkillsSync(_handoff(), _skillsNoPending);
      expect(result.hasWarnings, isTrue);
    });

    test('warning message mentions claudart save', () {
      final result = checkSkillsSync(_handoff(), _skillsNoPending);
      expect(result.issues.first.suggestion, contains('claudart save'));
    });

    test('warning when skills content is empty', () {
      final result = checkSkillsSync(_handoff(), '');
      expect(result.hasWarnings, isTrue);
    });

    test('clean when pending exists for different branch — different session',
        () {
      // Another branch's entry in pending doesn't count for current branch.
      final result = checkSkillsSync(
        _handoff(),
        _skillsWithPending('main'), // different branch
      );
      expect(result.hasWarnings, isTrue);
    });
  });

  group('checkSkillsSync — unconfirmed root cause', () {
    test('clean when root cause is placeholder', () {
      final result = checkSkillsSync(
        _handoff(rootCause: '_Not yet determined.'),
        _skillsNoPending,
      );
      expect(result.isClean, isTrue);
    });

    test('clean for blank handoff regardless of skills state', () {
      final result = checkSkillsSync(_blankHandoff, _skillsNoPending);
      expect(result.isClean, isTrue);
    });

    test('clean when both unconfirmed and no pending — fresh session', () {
      final result = checkSkillsSync(_blankHandoff, '');
      expect(result.isClean, isTrue);
    });
  });

  // ── checkHandoffStatus — debug ─────────────────────────────────────────────

  group('checkHandoffStatus — debug operation', () {
    test('clean when status is ready-for-debug', () {
      final result =
          checkHandoffStatus('debug', _handoff(status: 'ready-for-debug'));
      expect(result.isClean, isTrue);
    });

    test('clean when status is debug-in-progress', () {
      final result =
          checkHandoffStatus('debug', _handoff(status: 'debug-in-progress'));
      expect(result.isClean, isTrue);
    });

    test('error when status is suggest-investigating', () {
      final result = checkHandoffStatus(
          'debug', _handoff(status: 'suggest-investigating'));
      expect(result.hasErrors, isTrue);
    });

    test('error when status is needs-suggest', () {
      final result =
          checkHandoffStatus('debug', _handoff(status: 'needs-suggest'));
      expect(result.hasErrors, isTrue);
    });

    test('error message suggests running /suggest then /save', () {
      final result = checkHandoffStatus(
          'debug', _handoff(status: 'suggest-investigating'));
      expect(result.issues.first.suggestion, contains('/suggest'));
      expect(result.issues.first.suggestion, contains('/save'));
    });
  });

  // ── checkHandoffStatus — save operation ───────────────────────────────────

  group('checkHandoffStatus — save operation', () {
    test('clean when session has active content', () {
      final result = checkHandoffStatus('save', _handoff());
      expect(result.isClean, isTrue);
    });

    test('warning when handoff has no active content', () {
      final result = checkHandoffStatus('save', _blankHandoff);
      expect(result.hasWarnings, isTrue);
    });

    test('warning suggestion mentions claudart setup', () {
      final result = checkHandoffStatus('save', _blankHandoff);
      expect(result.issues.first.suggestion, contains('claudart setup'));
    });
  });

  // ── checkHandoffStatus — test operation ───────────────────────────────────

  group('checkHandoffStatus — test operation', () {
    test('always clean regardless of status', () {
      for (final status in [
        'suggest-investigating',
        'ready-for-debug',
        'debug-in-progress',
        'needs-suggest',
      ]) {
        final result =
            checkHandoffStatus('test', _handoff(status: status));
        expect(result.isClean, isTrue,
            reason: 'expected clean for status: $status');
      }
    });
  });

  // ── checkCoverageGaps ──────────────────────────────────────────────────────

  group('checkCoverageGaps', () {
    test('returns empty list when all scenarios covered', () {
      expect(checkCoverageGaps(_testFileAllCovered), isEmpty);
    });

    test('returns gap scenario names', () {
      final gaps = checkCoverageGaps(_testFileWithGaps);
      expect(gaps, hasLength(2));
      expect(gaps, contains('Empty state'));
      expect(gaps, contains('Rollback on failure'));
    });

    test('returns only gap rows from mixed table', () {
      final gaps = checkCoverageGaps(_testFileMixed);
      expect(gaps, hasLength(1));
      expect(gaps.first, equals('Edge case X'));
    });

    test('returns empty list for empty string', () {
      expect(checkCoverageGaps(''), isEmpty);
    });

    test('returns empty list when no table present', () {
      expect(checkCoverageGaps('# Just a heading\n\nSome text.'), isEmpty);
    });
  });

  // ── checkBranchSync ────────────────────────────────────────────────────────

  group('checkBranchSync', () {
    test('clean when branches match', () {
      final result = checkBranchSync(_handoff(), _branch);
      expect(result.isClean, isTrue);
    });

    test('warning when current branch differs from handoff branch', () {
      final result = checkBranchSync(_handoff(), 'main');
      expect(result.hasWarnings, isTrue);
    });

    test('warning message names both branches', () {
      final result = checkBranchSync(_handoff(), 'main');
      expect(result.issues.first.message, contains('main'));
      expect(result.issues.first.message, contains(_branch));
    });

    test('suggestion mentions switching back or setup', () {
      final result = checkBranchSync(_handoff(), 'main');
      expect(result.issues.first.suggestion, contains(_branch));
      expect(result.issues.first.suggestion, contains('claudart setup'));
    });

    test('clean when currentBranch is null — git context unavailable', () {
      final result = checkBranchSync(_handoff(), null);
      expect(result.isClean, isTrue);
    });

    test('clean when handoff has no active content', () {
      final result = checkBranchSync(_blankHandoff, 'main');
      expect(result.isClean, isTrue);
    });

    test('clean when handoff branch is unknown', () {
      // Handoff with no branch line resolves to "unknown" — no mismatch warning.
      final result = checkBranchSync('# Agent Handoff\n\n## Status\n\nready-for-debug\n\n## Bug\n\nBroken.\n', 'main');
      expect(result.isClean, isTrue);
    });
  });

  // ── runPreflight — combined ────────────────────────────────────────────────

  group('runPreflight — test operation', () {
    test('clean when handoff synced and no coverage gaps', () {
      final result = runPreflight(
        operation: 'test',
        handoffContent: _handoff(),
        skillsContent: _skillsWithPending(_branch),
        testFileContents: {'test_commands.md': _testFileAllCovered},
      );
      expect(result.isClean, isTrue);
    });

    test('warning when skills unsynced', () {
      final result = runPreflight(
        operation: 'test',
        handoffContent: _handoff(),
        skillsContent: _skillsNoPending,
      );
      expect(result.hasWarnings, isTrue);
    });

    test('warning when coverage gaps found', () {
      final result = runPreflight(
        operation: 'test',
        handoffContent: _blankHandoff,
        skillsContent: '',
        testFileContents: {'test_commands.md': _testFileWithGaps},
      );
      expect(result.hasWarnings, isTrue);
    });

    test('gap warning includes filename', () {
      final result = runPreflight(
        operation: 'test',
        handoffContent: _blankHandoff,
        skillsContent: '',
        testFileContents: {'test_commands.md': _testFileWithGaps},
      );
      expect(result.issues.first.message, contains('test_commands.md'));
    });

    test('merges skills warning and coverage warning', () {
      final result = runPreflight(
        operation: 'test',
        handoffContent: _handoff(),
        skillsContent: _skillsNoPending,
        testFileContents: {'test_commands.md': _testFileWithGaps},
      );
      expect(result.issues, hasLength(2));
    });
  });

  group('runPreflight — debug operation', () {
    test('clean when status ready and skills synced', () {
      final result = runPreflight(
        operation: 'debug',
        handoffContent: _handoff(status: 'ready-for-debug'),
        skillsContent: _skillsWithPending(_branch),
      );
      expect(result.isClean, isTrue);
    });

    test('error when status invalid — overrides other checks', () {
      final result = runPreflight(
        operation: 'debug',
        handoffContent: _handoff(status: 'suggest-investigating'),
        skillsContent: _skillsNoPending,
      );
      expect(result.hasErrors, isTrue);
    });

    test('reports both error and skills warning independently', () {
      final result = runPreflight(
        operation: 'debug',
        handoffContent: _handoff(
            status: 'suggest-investigating',
            rootCause: 'StateNotifier holds stale ref.'),
        skillsContent: _skillsNoPending,
      );
      // Error: wrong status. Warning: unsynced skills.
      expect(result.issues.length, greaterThanOrEqualTo(2));
    });
  });

  // ── SyncCheckResult helpers ────────────────────────────────────────────────

  group('SyncCheckResult', () {
    test('isClean when no issues', () {
      expect(SyncCheckResult.clean().isClean, isTrue);
    });

    test('merge combines issues from both results', () {
      const a = SyncCheckResult([
        SyncIssue(IssueSeverity.warning, 'warn A'),
      ]);
      const b = SyncCheckResult([
        SyncIssue(IssueSeverity.error, 'error B'),
      ]);
      final merged = a.merge(b);
      expect(merged.issues, hasLength(2));
      expect(merged.hasErrors, isTrue);
      expect(merged.hasWarnings, isTrue);
    });

    test('merge with clean result is identity', () {
      const a = SyncCheckResult([SyncIssue(IssueSeverity.warning, 'w')]);
      expect(a.merge(SyncCheckResult.clean()).issues, hasLength(1));
    });
  });
}
