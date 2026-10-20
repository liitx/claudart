import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/confirm_pending.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/pending_confirmation.dart';
import '../helpers/mocks.dart';
import '../helpers/project_fixture.dart';

const _projectRoot = ProjectFixture.root;
const _workspace = ProjectFixture.workspace;

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

MemoryFileIO _io() {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final registry = Registry.empty().add(entry);
  final io = MemoryFileIO();
  registry.save(io: io);
  return io;
}

void main() {
  group('confirm-pending — set', () {
    test('writes a pending confirmation to the workspace', () async {
      final io = _io();
      await runConfirmPending(
        ['--question', 'Save this?', '--on-confirm', 'claudart save'],
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      final loaded = PendingConfirmationStore.load(_workspace, io: io);
      expect(loaded, isNotNull);
      expect(loaded!.question, equals('Save this?'));
      expect(loaded.onConfirmCommand, equals('claudart save'));
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      await runZoned(
        () => runConfirmPending(
          ['--question', 'Save this?', '--on-confirm', 'claudart save'],
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(output.join('\n'), contains('Project  : my-app'));
    });

    test('exits 1 when --question is missing', () async {
      final io = _io();
      await expectLater(
        runConfirmPending(
          ['--on-confirm', 'claudart save'],
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when --on-confirm is missing', () async {
      final io = _io();
      await expectLater(
        runConfirmPending(
          ['--question', 'Save this?'],
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO();
      await expectLater(
        runConfirmPending(
          ['--question', 'q', '--on-confirm', 'claudart save'],
          io: io,
          projectRootOverride: '/not/registered',
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('confirm-pending — clear', () {
    test('removes an existing pending confirmation', () async {
      final io = _io();
      PendingConfirmationStore.write(
        _workspace,
        PendingConfirmation(
          question: 'q',
          onConfirmCommand: 'claudart save',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        io: io,
      );

      await runConfirmPending(
        ['--clear'],
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('is a no-op when nothing is pending', () async {
      final io = _io();
      await runConfirmPending(
        ['--clear'],
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('--clear takes priority even if --question/--on-confirm are also passed', () async {
      final io = _io();
      await runConfirmPending(
        ['--clear', '--question', 'q', '--on-confirm', 'claudart save'],
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );

      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });
  });
}
