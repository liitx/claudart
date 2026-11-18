// project_logger_test.dart — a command's records go to the logs of the project
// it ran in.
//
// Where a record lands is read off the file system: the project's own workspace
// logs, the global logs when no project is registered, and the global logs under
// the strictest protection when the registry cannot be read. Which logger was
// chosen shows in the row's own `sensitivityMode`.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/commands/support/project_logger.dart';
import 'package:claudart/config/paths.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/registry.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/mocks.dart';
import '../../helpers/project_fixture.dart';

const _projectRoot = ProjectFixture.root;
const _workspace = ProjectFixture.workspace;
final _globalInteractions =
    logFilePath(p.join(claudeDir, 'logs'), LogFile.interactions);
final _workspaceInteractions =
    logFilePath(logsDirFor(_workspace), LogFile.interactions);

MemoryFileIO _ioRegistering({bool sensitive = false}) {
  final io = MemoryFileIO();
  Registry.empty()
      .add(
        RegistryEntry(
          name: 'my-app',
          projectRoot: _projectRoot,
          workspacePath: _workspace,
          createdAt: '2026-01-01',
          lastSession: '2026-03-15',
          sensitivityMode: sensitive,
        ),
      )
      .save(io: io);
  return io;
}

void _recordRun(SessionLogger logger) => logger.logInteraction(
      rowKind: InteractionRowKind.run,
      command: 'status',
      outcome: 'failed',
      durationMs: 5,
    );

/// The one row at [path], decoded.
Map<String, dynamic> _row(MemoryFileIO io, String path) =>
    jsonDecode(io.read(path).trim()) as Map<String, dynamic>;

/// Whether the logger that wrote the row at [path] treats the project as
/// sensitive.
bool _writtenAsSensitive(MemoryFileIO io, String path) =>
    _row(io, path)[LogEntryField.sensitivityMode.name] as bool;

void main() {
  group('loggerForProject', () {
    test('a registered project\'s records go to its workspace logs', () {
      final io = _ioRegistering();
      _recordRun(loggerForProject(projectRoot: _projectRoot, io: io));
      expect(_writtenAsSensitive(io, _workspaceInteractions), isFalse);
      expect(io.read(_globalInteractions), isEmpty);
    });

    test('a sensitive project\'s records go to its workspace logs, written '
        'as sensitive', () {
      final io = _ioRegistering(sensitive: true);
      _recordRun(loggerForProject(projectRoot: _projectRoot, io: io));
      expect(_writtenAsSensitive(io, _workspaceInteractions), isTrue);
      expect(io.read(_globalInteractions), isEmpty);
    });

    test('a root with no registered project goes to the global logs', () {
      final io = _ioRegistering();
      _recordRun(loggerForProject(projectRoot: '/somewhere/else', io: io));
      expect(_writtenAsSensitive(io, _globalInteractions), isFalse);
      expect(io.read(_workspaceInteractions), isEmpty);
    });

    test('an unreadable registry writes to the global logs, as sensitive '
        'because it cannot say otherwise', () {
      final io = MemoryFileIO()..write(registryPath, '{not valid json');
      _recordRun(loggerForProject(projectRoot: _projectRoot, io: io));
      expect(_writtenAsSensitive(io, _globalInteractions), isTrue);
      expect(io.read(_workspaceInteractions), isEmpty);
    });

    group('with no root given, the git root of where it ran', () {
      late MockProcessRunner runner;
      setUp(() => runner = MockProcessRunner());

      void gitAnswers(String stdout, {int exitCode = 0}) => when(
            () => runner.runSync(any(), any(),
                workingDirectory: any(named: 'workingDirectory')),
          ).thenReturn(fakeResult(stdout, exitCode: exitCode));

      test('is the project whose records they are', () {
        gitAnswers('$_projectRoot\nmain\n');
        final io = _ioRegistering();
        _recordRun(loggerForProject(io: io, runner: runner));
        expect(_writtenAsSensitive(io, _workspaceInteractions), isFalse);
        expect(io.read(_globalInteractions), isEmpty);
      });

      test('outside a git repository goes to the global logs', () {
        gitAnswers('', exitCode: 128);
        final io = _ioRegistering();
        _recordRun(loggerForProject(io: io, runner: runner));
        expect(_writtenAsSensitive(io, _globalInteractions), isFalse);
        expect(io.read(_workspaceInteractions), isEmpty);
      });
    });
  });

  group('the binary\'s run boundary', () {
    final binary = File('bin/claudart.dart').readAsStringSync();

    test('chooses its logger through loggerForProject, for the selected project',
        () {
      expect(binary,
          contains('logger: loggerForProject(projectRoot: selectedRoot)'));
    });

    test('has no logger of its own that ignores the project', () {
      expect(binary, isNot(contains('SessionLogger.plain()')));
    });
  });
}
