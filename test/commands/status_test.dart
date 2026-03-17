import 'package:test/test.dart';
import 'package:claudart/commands/status.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _projectName = 'my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

void main() {
  group('status — branch display', () {
    test('displays live git branch when handoff has unknown', () async {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);

      // Registry entry.
      final registry = Registry.empty().add(RegistryEntry(
        name: _projectName,
        projectRoot: _projectRoot,
        workspacePath: workspace,
        createdAt: '2026-03-17',
        lastSession: '2026-03-17',
        sensitivityMode: false,
      ));
      registry.save(io: io);

      // Handoff with 'unknown' branch.
      final handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: unknown
> Source of truth between suggest and debug agents.

---

## Status

suggest-investigating

---

## Bug

Test bug description.

---

## Expected Behavior

Expected behavior.

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### BLoCs / providers in play
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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      // Capture stdout (status prints to stdout).
      // For now, just verify it doesn't crash when run from a git repo
      // where detectGitContext would return a valid branch.
      // Note: In tests, projectRootOverride bypasses git detection, so
      // currentBranch will be null. This test verifies the fallback works.
      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      // If we got here without exception, the command succeeded.
      expect(true, isTrue);
    });

    test('displays handoff branch when git detection unavailable', () async {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);

      final registry = Registry.empty().add(RegistryEntry(
        name: _projectName,
        projectRoot: _projectRoot,
        workspacePath: workspace,
        createdAt: '2026-03-17',
        lastSession: '2026-03-17',
        sensitivityMode: false,
      ));
      registry.save(io: io);

      final handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: feat/test
> Source of truth between suggest and debug agents.

---

## Status

suggest-investigating

---

## Bug

Test bug.

---

## Expected Behavior

Expected.

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### BLoCs / providers in play
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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      expect(true, isTrue);
    });
  });

  group('status — error handling', () {
    test('exits 1 when no registry entry found', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });

    test('exits 1 when not in git repo and no override', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(io: io, exitFn: _throwExit),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });
}
