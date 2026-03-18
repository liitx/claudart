import 'package:test/test.dart';
import 'package:claudart/commands/preflight_cmd.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';

// Handoff with confirmed root cause (so checkSkillsSync will warn without skills).
const _confirmedHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: feat/fix

---

## Status

ready-for-debug

---

## Bug

Widget does not update.

---

## Expected Behavior

Widget updates on state change.

---

## Root Cause

StateNotifier holds stale reference.

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

// Blank handoff — no root cause, no active content.
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

const _skillsWithPending = '''# Accumulated Skills

---

## Pending

> Confirmed facts from in-progress sessions.

- `feat/fix` (2026-03-16): root cause — StateNotifier holds stale reference.

---

## Hot Paths

_No sessions recorded yet._
''';

/// Thrown by the injected exitFn so tests can assert exit-code behaviour
/// without terminating the process.
class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

/// Builds a registry-seeded MemoryFileIO.
MemoryFileIO _io({
  bool withHandoff = true,
  bool withSkills = false,
  bool confirmedRootCause = false,
  bool pendingInSkills = false,
  Map<String, String> commandFiles = const {},
}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final handoffContent = confirmedRootCause ? _confirmedHandoff : _blankHandoff;
  final io = MemoryFileIO(
    files: {
      if (withHandoff) handoffPathFor(_workspace): handoffContent,
      if (withSkills && pendingInSkills)
        skillsPathFor(_workspace): _skillsWithPending,
      if (withSkills && !pendingInSkills)
        skillsPathFor(_workspace):
            '# Accumulated Skills\n\n## Pending\n\n_Nothing yet._\n',
      for (final e in commandFiles.entries)
        '${claudeCommandsDirFor(_workspace)}/${e.key}': e.value,
    },
  );
  Registry.empty().add(entry).save(io: io);
  return io;
}

void main() {
  // ── Registry errors ────────────────────────────────────────────────────────

  group('preflight — registry errors', () {
    test('exits when project not in registry', () async {
      // Empty registry — no entry for _projectRoot.
      final io = MemoryFileIO();
      Registry.empty().save(io: io);

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(1));
    });
  });

  // ── Clean result ───────────────────────────────────────────────────────────

  group('preflight — clean result', () {
    test('exits 0 when handoff is blank and skills are empty', () async {
      final io = _io(withHandoff: true, withSkills: false);

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      // Blank handoff means no root cause to sync — clean.
      expect(caught?.code ?? 0, equals(0));
    });

    test('exits 0 when root cause confirmed and pending entry exists',
        () async {
      final io = _io(
        withHandoff: true,
        withSkills: true,
        confirmedRootCause: true,
        pendingInSkills: true,
      );

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'debug',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });
  });

  // ── Warning result (exits 0 — workflow continues) ──────────────────────────

  group('preflight — warning result exits 0', () {
    test('exits 0 even when skills are out of sync (warning only)', () async {
      // Root cause confirmed but no pending entry → warning, not error.
      final io = _io(
        withHandoff: true,
        withSkills: false,
        confirmedRootCause: true,
      );

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });
  });

  // ── Error result (exits 1 — workflow blocked) ──────────────────────────────

  group('preflight — error result exits 1', () {
    test('exits 1 when debug operation has wrong handoff status', () async {
      // Blank handoff has status suggest-investigating — invalid for debug.
      final io = _io(withHandoff: true, withSkills: false);

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'debug',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(1));
    });
  });

  // ── Missing files ──────────────────────────────────────────────────────────

  group('preflight — missing files', () {
    test('handles missing handoff gracefully (treats as empty)', () async {
      // No handoff file — blank content → clean for test op → exits 0.
      final io = _io(withHandoff: false, withSkills: false);
      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });

    test('handles missing skills file gracefully (treats as empty)', () async {
      final io = _io(withHandoff: true, withSkills: false);
      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });
  });

  // ── Test operation: coverage gap file loading ──────────────────────────────

  group('preflight — test operation reads command files', () {
    test('loads coverage table files when operation is test', () async {
      const coverageWithGap = '''
| Scenario     | Covered |
|--------------|---------|
| Happy path   | ✓       |
| Edge case    | —       |
''';
      final io = _io(
        withHandoff: true,
        withSkills: false,
        commandFiles: {'test_foo.md': coverageWithGap},
      );

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      // Gap detected → warning → exits 0 (not blocked).
      expect(caught?.code ?? 0, equals(0));
    });

    test('does not load command files when operation is not test', () async {
      // Even with a gap file present, save op ignores test files.
      const coverageWithGap = '''
| Scenario   | Covered |
|------------|---------|
| Edge case  | —       |
''';
      // Confirmed handoff with pending skills so save op is clean.
      final io = _io(
        withHandoff: true,
        withSkills: true,
        confirmedRootCause: true,
        pendingInSkills: true,
        commandFiles: {'test_foo.md': coverageWithGap},
      );

      _ExitException? caught;
      try {
        await runPreflightCmd(
          'save',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });

    test('handles missing commands directory gracefully', () async {
      // No command files written — dirExists returns false → exits 0.
      final io = _io(withHandoff: true, withSkills: false);
      _ExitException? caught;
      try {
        await runPreflightCmd(
          'test',
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught?.code ?? 0, equals(0));
    });
  });
}
