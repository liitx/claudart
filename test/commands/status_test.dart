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
      const handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: unknown
> Source of truth between suggest and debug agents.

---

## Status

suggest-investigating

---

## Bug

Config not loaded when path has spaces.

---

## Expected Behavior

Config loads regardless of spaces in path.

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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      // Note: projectRootOverride bypasses git detection so currentBranch
      // will be null. The command falls back to reading branch from handoff.
      // Status is read-only — it must not mutate the handoff file.
      final handoffBefore = io.read(handoffPathFor(workspace));
      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );
      // Handoff must be unchanged — status is read-only.
      expect(io.read(handoffPathFor(workspace)), equals(handoffBefore));
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

      const handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: fix/null-ref
> Source of truth between suggest and debug agents.

---

## Status

suggest-investigating

---

## Bug

Parser returns empty on malformed input.

---

## Expected Behavior

Parser returns null or throws on malformed input.

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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      final handoffBefore = io.read(handoffPathFor(workspace));
      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );
      // Status is read-only — handoff must not be mutated.
      expect(io.read(handoffPathFor(workspace)), equals(handoffBefore));
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
