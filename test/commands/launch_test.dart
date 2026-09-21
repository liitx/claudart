import 'dart:async';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/launch.dart';
import 'package:claudart/git_utils.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/session/workspace_guard.dart';
import '../helpers/mocks.dart';
import '../matrix/handoff_expectation.dart';
import '../matrix/handoff_status_matrix.dart' as handoff_matrix;
import '../matrix/handoff_status_type.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';
const _claudeLink = '/projects/my-app/.claude';

const _activeHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: feat/fix

---

## Status

ready-for-debug

---

## Bug

Something is broken.

---

## Expected Behavior

It should work.

---

## Root Cause

StateNotifier holds stale ref.

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
Traced call through config loader.

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

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

/// Builds an IO pre-seeded with one registry entry.
MemoryFileIO _io({
  bool withHandoff = false,
  bool withLink = false,
  bool withRealDir = false,
  bool withLock = false,
  bool sensitivityMode = false,
}) {
  final entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
    sensitivityMode: sensitivityMode,
  );
  final io = MemoryFileIO(
    files: {
      if (withHandoff) handoffPathFor(_workspace): _activeHandoff,
    },
    links: {if (withLink) _claudeLink},
    dirs: {if (withRealDir) _claudeLink},
  );
  if (withLock) {
    io.write(p.join(_workspace, 'workspace.lock'), 'setup');
  }
  Registry.empty().add(entry).save(io: io);
  return io;
}

void main() {
  handoff_matrix.assertNoGaps();

  group('launch — empty registry', () {
    test('exits when no projects registered', () async {
      final io = MemoryFileIO();
      Registry.empty().save(io: io);

      await expectLater(
        runLauncher(
          io: io,
          projectRootOverride: null,
          pickFn: (_) => 0,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('launch — project list', () {
    test('lists registered projects without error', () async {
      final io = _io(withHandoff: true, withLink: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : ActiveMenu.back;
        },
        exitFn: _throwExit,
      );
      expect(pickCall, equals(2));
      handoff_matrix.cover(HandoffStatusType.readyForDebug, HandoffExpectation.debug);
    });

    test('a real .claude/ directory (symlink was never possible) shows as '
        'linked, not unlinked', () async {
      final io = _io(withHandoff: true, withLink: false, withRealDir: true);
      List<String>? capturedItems;
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (items) {
          capturedItems ??= items;
          pickCall++;
          return pickCall == 1 ? 0 : ActiveMenu.back;
        },
        exitFn: _throwExit,
      );
      // Same colour/dot convention _buildProjectItems uses: green ● for
      // linked, dim ○ for not. A real directory must render as linked.
      final projectRow = capturedItems!.firstWhere((i) => i.contains('my-app'));
      expect(projectRow, contains('●'));
      expect(projectRow, isNot(contains('○')));
    });

    test('highlights current project when cwd matches', () async {
      final io = _io(withHandoff: false, withLink: false);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: _projectRoot,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : FreshMenu.back;
        },
        exitFn: _throwExit,
      );
      expect(pickCall, equals(2));
    });
  });

  group('launch — locked workspace', () {
    test('routes to kill when workspace is locked and user confirms', () async {
      final io = _io(withHandoff: true, withLink: true, withLock: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : LockedMenu.kill;
        },
        confirmFn: (_) => true,
        exitFn: _throwExit,
      );
      expect(isLocked(_workspace, io: io), isFalse);
    });

    test('does nothing when locked and user picks Back', () async {
      final io = _io(withHandoff: true, withLink: true, withLock: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : LockedMenu.back;
        },
        exitFn: _throwExit,
      );
      expect(isLocked(_workspace, io: io), isTrue);
    });
  });

  group('launch — active session routing', () {
    test('kill from resume menu leaves the symlink in place', () async {
      final io = _io(withHandoff: true, withLink: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : ActiveMenu.kill;
        },
        confirmFn: (_) => true,
        exitFn: _throwExit,
      );
      // kill closes the session, it does not deregister the project —
      // unlink is what removes the symlink.
      expect(io.linkExists(_claudeLink), isTrue);
    });

    test('resume picks action without error (display only)', () async {
      final io = _io(withHandoff: true, withLink: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : ActiveMenu.resume;
        },
        exitFn: _throwExit,
      );
      expect(io.linkExists(_claudeLink), isTrue);
    });
  });

  group('launch — fresh workspace', () {
    test('offers start new session when no handoff', () async {
      final io = _io(withHandoff: false, withLink: false);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : FreshMenu.back;
        },
        exitFn: _throwExit,
      );
      final archived = io.files.keys
          .where((k) => k.startsWith(p.join(_workspace, 'archive')))
          .toList();
      expect(archived, isEmpty);
    });
  });

  group('launch — register unregistered project', () {
    test('routes to runLink with injected io when user picks Register', () async {
      final io = _io();
      const unregisteredRoot = '/projects/other-app';

      await runLauncher(
        io: io,
        projectRootOverride: unregisteredRoot,
        pickFn: (_) => registerChoice(1),
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      final registry = Registry.load(io: io);
      expect(registry.findByProjectRoot(unregisteredRoot), isNotNull);
    });
  });

  group('launch — long project name', () {
    test('does not throw when project name exceeds 35 characters', () async {
      const longName = 'my-company-internal-flutter-app-with-extras';
      const entry = RegistryEntry(
        name: longName,
        projectRoot: '/projects/$longName',
        workspacePath: '/workspaces/$longName',
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
        sensitivityMode: false,
      );
      final io = MemoryFileIO();
      Registry.empty().add(entry).save(io: io);

      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : FreshMenu.back;
        },
        exitFn: _throwExit,
      );
      expect(pickCall, equals(2));
    });
  });

  group('launch — sensitivity mode display', () {
    test('does not crash when sensitivity mode is on', () async {
      final io = _io(withHandoff: false, withLink: false, sensitivityMode: true);
      var pickCall = 0;
      await runLauncher(
        io: io,
        projectRootOverride: null,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : FreshMenu.back;
        },
        exitFn: _throwExit,
      );
      expect(pickCall, equals(2));
    });
  });

  group('launch — branch display', () {
    test('prefers live git branch over stale handoff branch for the cwd project', () async {
      final realGit = detectGitContext();
      // Only meaningful inside a real git checkout — skip otherwise.
      if (realGit == null) return;

      final io = MemoryFileIO(
        files: {handoffPathFor(_workspace): _activeHandoff},
      );
      Registry.empty()
          .add(RegistryEntry(
            name: 'my-app',
            projectRoot: realGit.root,
            workspacePath: _workspace,
            createdAt: '2026-01-01',
            lastSession: '2026-03-15',
            sensitivityMode: false,
          ))
          .save(io: io);

      final output = <String>[];
      var pickCall = 0;
      await runZoned(
        () => runLauncher(
          io: io,
          projectRootOverride: null,
          pickFn: (_) {
            pickCall++;
            return pickCall == 1 ? 0 : ActiveMenu.back;
          },
          exitFn: _throwExit,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );

      final printed = output.join('\n');
      // _activeHandoff stores "Branch: feat/fix" — the live branch must win.
      expect(printed, contains('Branch : ${realGit.branch}'));
      expect(printed, isNot(contains('Branch : feat/fix')));
    });

    test('falls back to handoff branch for a project that is not the cwd project', () async {
      final io = _io(withHandoff: true, withLink: false);
      final output = <String>[];
      var pickCall = 0;
      await runZoned(
        () => runLauncher(
          io: io,
          // Never matches the real cwd's git root, so this entry is not
          // "the current project" — its stored branch must be shown as-is.
          projectRootOverride: null,
          pickFn: (_) {
            pickCall++;
            return pickCall == 1 ? 0 : ActiveMenu.back;
          },
          exitFn: _throwExit,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );

      expect(output.join('\n'), contains('Branch : feat/fix'));
    });
  });
}
