import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/kill.dart';
import 'package:claudart/file_io.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/session/workspace_guard.dart';
import '../helpers/mocks.dart';

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

/// Builds a registry pre-seeded with one entry for _projectRoot → _workspace.
MemoryFileIO _io({bool withHandoff = true, bool withLink = true}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final registry = Registry.empty().add(entry);
  final io = MemoryFileIO(
    files: {
      if (withHandoff) handoffPathFor(_workspace): _activeHandoff,
    },
    links: {if (withLink) _claudeLink},
  );
  // Write registry so Registry.load() finds it.
  registry.save(io: io);
  return io;
}

void main() {
  group('kill — success path', () {
    test('archives handoff', () async {
      final io = _io();
      await runKill(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: (code) => throw _ExitException(code),
      );
      final archived = io.files.keys
          .where((k) => k.startsWith(p.join(_workspace, 'archive')))
          .toList();
      expect(archived, hasLength(1));
    });

    test('resets handoff to blank', () async {
      final io = _io();
      await runKill(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: (code) => throw _ExitException(code),
      );
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, isNot(contains('Something is broken')));
    });

    test('removes symlink', () async {
      final io = _io();
      await runKill(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: (code) => throw _ExitException(code),
      );
      expect(io.linkExists(_claudeLink), isFalse);
    });

    test('updates registry lastSession', () async {
      final io = _io();
      await runKill(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: (code) => throw _ExitException(code),
      );
      final registry = Registry.load(io: io);
      final entry = registry.findByName('my-app')!;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect(entry.lastSession, equals(today));
    });
  });

  group('kill — rejected by user', () {
    test('leaves handoff intact when user declines', () async {
      final io = _io();
      await expectLater(
        runKill(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false, // decline on first confirmation
          exitFn: (code) => throw _ExitException(code),
        ),
        throwsA(isA<_ExitException>()),
      );
      // Handoff should still contain the active content.
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Something is broken'));
    });
  });

  group('kill — locked workspace', () {
    test('leaves lock intact when user declines clear', () async {
      final io = _io();
      // Plant a lock file to simulate interrupted state.
      io.write(p.join(_workspace, 'workspace.lock'), 'setup');

      await expectLater(
        runKill(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false, // decline clear lock
          exitFn: (code) => throw _ExitException(code),
        ),
        throwsA(isA<_ExitException>()),
      );

      // Workspace should still be locked.
      expect(isLocked(_workspace, io: io), isTrue);
    });

    test('proceeds after user confirms lock clear', () async {
      final io = _io();
      io.write(p.join(_workspace, 'workspace.lock'), 'setup');

      await runKill(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true, // accept all prompts including lock clear
        exitFn: (code) => throw _ExitException(code),
      );

      expect(isLocked(_workspace, io: io), isFalse);
    });
  });

  group('kill — error handling', () {
    test('exits with code 1 when closeSession fails', () async {
      // Simulate unlink failure so closeSession throws SessionCloseException.
      // Rollback mechanics (handoff restored, archive deleted) are verified in
      // session_ops_test.dart. This test only verifies kill's error response.
      final io = _FailOnUnlinkIO(delegate: _io());
      _ExitException? caught;
      try {
        await runKill(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          exitFn: (code) => throw _ExitException(code),
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(1));
    });
  });
}

/// Thrown by the injected exitFn so tests can assert on exit-path behaviour
/// without actually terminating the process.
class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

/// Delegates all ops to [delegate] but throws on deleteLink.
class _FailOnUnlinkIO implements FileIO {
  final MemoryFileIO delegate;
  _FailOnUnlinkIO({required this.delegate});

  @override
  void deleteLink(String path) => throw Exception('simulated unlink failure');

  @override
  String read(String path) => delegate.read(path);
  @override
  void write(String path, String content) => delegate.write(path, content);
  @override
  void delete(String path) => delegate.delete(path);
  @override
  bool fileExists(String path) => delegate.fileExists(path);
  @override
  bool dirExists(String path) => delegate.dirExists(path);
  @override
  void createDir(String path) => delegate.createDir(path);
  @override
  List<String> listFiles(String d, {String? extension}) =>
      delegate.listFiles(d, extension: extension);
  @override
  bool linkExists(String path) => delegate.linkExists(path);
  @override
  void createLink(String linkPath, String targetPath) =>
      delegate.createLink(linkPath, targetPath);
}
