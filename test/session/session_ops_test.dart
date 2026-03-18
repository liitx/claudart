import 'package:test/test.dart';
import 'package:claudart/session/session_ops.dart';
import 'package:claudart/file_io.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/handoff_template.dart';
import '../helpers/mocks.dart';

const _workspace = '/workspace/my-app';
const _project = '/projects/my-app';
const _claudeLink = '/projects/my-app/.claude';

const _activeHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: feat/fix

---

## Status

ready-for-debug

---

## Bug

Widget does not update after state change.
''';

MemoryFileIO _io({
  bool withHandoff = true,
  bool withLink = true,
}) =>
    MemoryFileIO(
      files: {
        if (withHandoff) handoffPathFor(_workspace): _activeHandoff,
      },
      links: {if (withLink) _claudeLink},
    );

void main() {
  group('archiveHandoff', () {
    test('writes file at correct archive path', () {
      final io = _io(withLink: false);
      archiveHandoff(_workspace, _activeHandoff, 'fix/null-ref', io: io);
      final files = io.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(files, hasLength(1));
    });

    test('filename contains sanitised branch name', () {
      final io = _io(withLink: false);
      archiveHandoff(_workspace, _activeHandoff, 'fix/null-ref-v2', io: io);
      final key = io.files.keys
          .firstWhere((k) => k.startsWith(archiveDirFor(_workspace)));
      expect(key, contains('fix_null-ref-v2'));
    });

    test('archived content matches original handoff', () {
      final io = _io(withLink: false);
      archiveHandoff(_workspace, _activeHandoff, 'main', io: io);
      final key = io.files.keys
          .firstWhere((k) => k.startsWith(archiveDirFor(_workspace)));
      expect(io.read(key), equals(_activeHandoff));
    });
  });

  group('resetHandoff', () {
    test('overwrites handoff with blank template', () {
      final io = _io(withLink: false);
      resetHandoff(_workspace, io: io);
      expect(io.read(handoffPathFor(_workspace)), equals(blankHandoff));
    });

    test('blank handoff does not contain active bug content', () {
      final io = _io(withLink: false);
      resetHandoff(_workspace, io: io);
      expect(
        io.read(handoffPathFor(_workspace)),
        isNot(contains('Widget does not update')),
      );
    });
  });

  group('removeSessionLink', () {
    test('removes .claude symlink from project root', () {
      final io = _io();
      removeSessionLink(_project, io: io);
      expect(io.linkExists(_claudeLink), isFalse);
    });

    test('is safe when no symlink exists', () {
      final io = _io(withLink: false);
      expect(() => removeSessionLink(_project, io: io), returnsNormally);
    });
  });

  group('closeSession — success path', () {
    test('archives handoff', () async {
      final io = _io();
      await closeSession(_workspace, _project, io: io);
      final archived = io.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(archived, hasLength(1));
    });

    test('resets handoff to blank', () async {
      final io = _io();
      await closeSession(_workspace, _project, io: io);
      expect(io.read(handoffPathFor(_workspace)), equals(blankHandoff));
    });

    test('removes .claude symlink', () async {
      final io = _io();
      await closeSession(_workspace, _project, io: io);
      expect(io.linkExists(_claudeLink), isFalse);
    });

    test('leaves no partial state after success', () async {
      final io = _io();
      await closeSession(_workspace, _project, io: io);
      // Archive written, handoff reset, symlink gone.
      final archived = io.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(archived, hasLength(1));
      expect(io.read(handoffPathFor(_workspace)), equals(blankHandoff));
      expect(io.linkExists(_claudeLink), isFalse);
    });
  });

  group('closeSession — empty handoff', () {
    test('archives with unknown branch when handoff is empty', () async {
      final io = _io(withHandoff: false);
      // Write empty handoff so closeSession reads it.
      io.write(handoffPathFor(_workspace), '');
      await closeSession(_workspace, _project, io: io);
      final archived = io.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(archived, hasLength(1));
      expect(archived.first, contains('unknown'));
    });
  });

  group('closeSession — rollback on step 2 failure (reset fails)', () {
    test('archive is deleted when reset throws', () async {
      final io = _FailOnWriteIO(
        failPath: handoffPathFor(_workspace),
        failAfter: 0, // archive writes to a different path; this fails the first write to handoffPath (reset)
        delegate: _io(),
      );
      await expectLater(
        closeSession(_workspace, _project, io: io),
        throwsA(isA<SessionCloseException>()),
      );
      final archived = io.delegate.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(archived, isEmpty);
    });

    test('exception identifies the failed step', () async {
      final io = _FailOnWriteIO(
        failPath: handoffPathFor(_workspace),
        failAfter: 0,
        delegate: _io(),
      );
      try {
        await closeSession(_workspace, _project, io: io);
        fail('expected exception');
      } on SessionCloseException catch (e) {
        expect(e.failedStep, equals('reset'));
      }
    });
  });

  group('closeSession — rollback on step 3 failure (unlink fails)', () {
    test('handoff is restored when unlink throws', () async {
      final io = _FailOnUnlinkIO(delegate: _io());
      await expectLater(
        closeSession(_workspace, _project, io: io),
        throwsA(isA<SessionCloseException>()),
      );
      expect(io.delegate.read(handoffPathFor(_workspace)), equals(_activeHandoff));
    });

    test('archive is deleted when unlink throws', () async {
      final io = _FailOnUnlinkIO(delegate: _io());
      await expectLater(
        closeSession(_workspace, _project, io: io),
        throwsA(isA<SessionCloseException>()),
      );
      final archived = io.delegate.files.keys
          .where((k) => k.startsWith(archiveDirFor(_workspace)))
          .toList();
      expect(archived, isEmpty);
    });

    test('exception identifies the failed step', () async {
      final io = _FailOnUnlinkIO(delegate: _io());
      try {
        await closeSession(_workspace, _project, io: io);
        fail('expected exception');
      } on SessionCloseException catch (e) {
        expect(e.failedStep, equals('unlink'));
      }
    });
  });
}

// ── Test helpers ─────────────────────────────────────────────────────────────

/// Delegates all ops to [delegate] but throws on the Nth write to [failPath].
class _FailOnWriteIO implements FileIO {
  final MemoryFileIO delegate;
  final String failPath;
  final int failAfter;
  int _writes = 0;

  _FailOnWriteIO({
    required this.delegate,
    required this.failPath,
    required this.failAfter,
  });

  @override
  void write(String path, String content) {
    if (path == failPath) {
      _writes++;
      if (_writes > failAfter) throw Exception('simulated write failure');
    }
    delegate.write(path, content);
  }

  @override String read(String path) => delegate.read(path);
  @override void delete(String path) => delegate.delete(path);
  @override bool fileExists(String path) => delegate.fileExists(path);
  @override bool dirExists(String path) => delegate.dirExists(path);
  @override void createDir(String path) => delegate.createDir(path);
  @override List<String> listFiles(String d, {String? extension}) =>
      delegate.listFiles(d, extension: extension);
  @override bool linkExists(String path) => delegate.linkExists(path);
  @override void deleteLink(String path) => delegate.deleteLink(path);
  @override void createLink(String linkPath, String targetPath) =>
      delegate.createLink(linkPath, targetPath);
}

/// Delegates all ops to [delegate] but throws on deleteLink.
class _FailOnUnlinkIO implements FileIO {
  final MemoryFileIO delegate;
  _FailOnUnlinkIO({required this.delegate});

  @override
  void deleteLink(String path) => throw Exception('simulated unlink failure');

  @override String read(String path) => delegate.read(path);
  @override void write(String path, String content) => delegate.write(path, content);
  @override void delete(String path) => delegate.delete(path);
  @override bool fileExists(String path) => delegate.fileExists(path);
  @override bool dirExists(String path) => delegate.dirExists(path);
  @override void createDir(String path) => delegate.createDir(path);
  @override List<String> listFiles(String d, {String? extension}) =>
      delegate.listFiles(d, extension: extension);
  @override bool linkExists(String path) => delegate.linkExists(path);
  @override void createLink(String linkPath, String targetPath) =>
      delegate.createLink(linkPath, targetPath);
}
