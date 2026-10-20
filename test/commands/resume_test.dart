import 'dart:async';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/resume.dart';
import 'package:claudart/git_utils.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/session/archive_entry.dart';
import 'package:claudart/workspace/workspace_index.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

const _archivedHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-01 | Branch: fix/null-ref

---

## Status

debug-complete

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
''';

MemoryFileIO _io({bool withArchive = true}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final io = MemoryFileIO(dirs: {_projectRoot});
  Registry.empty().add(entry).save(io: io);

  if (withArchive) {
    final archiveEntry = ArchiveEntry(
      id: 'e1',
      kind: ArchiveKind.archive,
      description: 'Config loader fix',
      branch: 'fix/null-ref',
      createdAt: DateTime.utc(2026, 3, 1),
      handoffFile: 'handoff_e1.md',
    );
    appendToIndex(_workspace, archiveEntry, io: io);
    io.write(p.join(archiveDirFor(_workspace), 'handoff_e1.md'), _archivedHandoff);
  }
  return io;
}

void main() {
  group('resume — pre-populates setup from the newest archive', () {
    test('exits 0 with a message when there are no archives', () async {
      final io = _io(withArchive: false);
      await expectLater(
        runResume(
          confirmFn: unscriptedConfirm,
          
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO();
      await expectLater(
        runResume(
          confirmFn: unscriptedConfirm,
          
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });

    test('writes a handoff pre-filled from the archived Bug/Expected/Files', () async {
      final io = _io();
      await runResume(
        io: io,
        projectRootOverride: _projectRoot,
        // Accept every default by returning null (matches promptWithDefault's
        // "press enter to accept" behavior); confirm the final write.
        promptFn: (q, {optional = false}) => null,
        confirmFn: (_) => true,
        exitFn: _throwExit,
      );
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Config not loaded when path has spaces.'));
      expect(handoff, contains('Config loads regardless of spaces in path.'));
    });

    test('does not disable live git branch detection when run for real', () async {
      // Regression: runResume used to pass its own *resolved* projectRoot to
      // runSetup as projectRootOverride, which makes runSetup skip live git
      // detection entirely (the test-bypass convention every command uses) —
      // silently breaking branch detection for a real, live invocation with
      // no override of its own. Only meaningful inside a real git checkout.
      final realGit = detectGitContext();
      if (realGit == null) return;

      final entry = RegistryEntry(
        name: 'my-app',
        projectRoot: realGit.root,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      );
      final io = MemoryFileIO(dirs: {realGit.root});
      Registry.empty().add(entry).save(io: io);
      appendToIndex(
        _workspace,
        ArchiveEntry(
          id: 'e1',
          kind: ArchiveKind.archive,
          description: 'fix',
          branch: 'some-other-branch',
          createdAt: DateTime.utc(2026, 3, 1),
          handoffFile: 'handoff_e1.md',
        ),
        io: io,
      );
      io.write(p.join(archiveDirFor(_workspace), 'handoff_e1.md'), _archivedHandoff);

      final output = <String>[];
      await runZoned(
        () => runResume(
          io: io,
          // No projectRootOverride here — this is the live-invocation path.
          promptFn: (q, {optional = false}) => null,
          confirmFn: (_) => true,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );

      // The written handoff's branch must be the real detected branch, not
      // "unknown" (which is what a swallowed detection falls back to).
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Branch: ${realGit.branch}'));
    });
  });
}
