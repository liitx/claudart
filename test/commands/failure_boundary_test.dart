// failure_boundary_test.dart — every error that reaches the top of a command is
// mapped to a FailureType and logged before the process exits.
//
// A typed failure keeps its own type. Anything else becomes
// FailureType.unexpectedFailure, a marker that a type is missing, and is logged
// all the same, so no failure is dropped for lacking a type.

import 'dart:convert';

import 'package:claudart/commands/failure_boundary.dart';
import 'package:claudart/errors/claudart_exception.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/logging/log_protection.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/mocks.dart';
import 'package:claudart/logging/log_file.dart';
import '../helpers/project_fixture.dart';

const _projectRoot = ProjectFixture.root;
const _workspace = ProjectFixture.workspace;
const _command = 'debug';

MemoryFileIO _io({bool registered = true}) {
  final io = MemoryFileIO();
  if (registered) {
    Registry.empty()
        .add(
          const RegistryEntry(
            name: 'my-app',
            projectRoot: _projectRoot,
            workspacePath: _workspace,
            createdAt: '2026-01-01',
            lastSession: '2026-03-15',
          ),
        )
        .save(io: io);
  }
  return io;
}

List<Map<String, dynamic>> _errors(MemoryFileIO io, String logsDir) => [
      for (final line in io.read(logFilePath(logsDir, LogFile.errors)).split('\n'))
        if (line.isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ];

void main() {
  group('reportFailure — a typed failure', () {
    final typed = ClaudartException(FailureType.stepTimedOut);

    test('is returned unchanged, keeping its FailureType', () {
      final reported = reportFailure(
        command: _command,
        error: typed,
        projectRoot: _projectRoot,
        io: _io(),
      );
      expect(reported, same(typed));
    });

    test('is logged by its error type and failure type', () {
      final io = _io();
      reportFailure(
        command: _command,
        error: typed,
        projectRoot: _projectRoot,
        io: io,
      );
      final entry = _errors(io, logsDirFor(_workspace)).single;
      expect(
        entry[LogEntryField.outcome.name],
        FailureType.stepTimedOut.errorType.name,
      );
      expect(
        entry[LogEntryField.fingerprint.name],
        '$_command.${FailureType.stepTimedOut.name}',
      );
    });
  });

  group('reportFailure — an untyped error', () {
    final cause = StateError('boom');

    test('becomes unexpectedFailure and keeps its message as the cause', () {
      final reported = reportFailure(
        command: _command,
        error: cause,
        projectRoot: _projectRoot,
        io: _io(),
      );
      expect(reported.failureType, FailureType.unexpectedFailure);
      expect(
        reported.context[FailureContextKey.cause.name],
        contains('boom'),
      );
    });

    test('is logged as unexpectedFailure, with its message', () {
      final io = _io();
      reportFailure(
        command: _command,
        error: cause,
        projectRoot: _projectRoot,
        io: io,
      );
      final entry = _errors(io, logsDirFor(_workspace)).single;
      expect(
        entry[LogEntryField.outcome.name],
        FailureType.unexpectedFailure.errorType.name,
      );
      expect(
        entry[LogEntryField.fingerprint.name],
        '$_command.${FailureType.unexpectedFailure.name}',
      );
      expect(entry[LogEntryField.reason.name], contains('boom'));
    });

    test('logs the stack trace when one is given', () {
      final io = _io();
      reportFailure(
        command: _command,
        error: cause,
        stackTrace: StackTrace.fromString('the stack'),
        projectRoot: _projectRoot,
        io: io,
      );
      expect(
        _errors(io, logsDirFor(_workspace)).single[LogEntryField.stack.name],
        'the stack',
      );
    });
  });

  group('reportFailure — a sensitive project with an unreadable token map', () {
    MemoryFileIO sensitiveIo() {
      final io = MemoryFileIO();
      Registry.empty()
          .add(
            const RegistryEntry(
              name: 'my-app',
              projectRoot: _projectRoot,
              workspacePath: _workspace,
              createdAt: '2026-01-01',
              lastSession: '2026-03-15',
              sensitivityMode: true,
            ),
          )
          .save(io: io);
      io.write(tokenMapPathFor(_workspace), '{not valid json');
      return io;
    }

    test('still logs the failure, but never its raw message', () {
      final io = sensitiveIo();
      final reported = reportFailure(
        command: _command,
        error: StateError('VolumeBloc exploded'),
        stackTrace: StackTrace.fromString('at VolumeBloc.process'),
        projectRoot: _projectRoot,
        io: io,
      );
      expect(reported.failureType, FailureType.unexpectedFailure);
      final entry = _errors(io, logsDirFor(_workspace)).single;
      expect(entry[LogEntryField.reason.name], isNot(contains('VolumeBloc')));
      expect(entry.containsKey(LogEntryField.stack.name), isFalse);
      expect(
        entry[LogEntryField.fingerprint.name],
        '$_command.${FailureType.unexpectedFailure.name}',
      );
    });
  });

  group('reportFailure — where it is logged', () {
    test('a registered project logs to its workspace', () {
      final io = _io();
      reportFailure(
        command: _command,
        error: StateError('boom'),
        projectRoot: _projectRoot,
        io: io,
      );
      expect(_errors(io, logsDirFor(_workspace)), hasLength(1));
    });

    test('an unreadable registry cannot say which project, so no text is '
        'logged, and the boundary itself does not throw', () {
      final io = MemoryFileIO(files: {registryPath: '{not valid json'});
      final reported = reportFailure(
        command: _command,
        error: StateError('VolumeBloc exploded'),
        projectRoot: _projectRoot,
        io: io,
      );
      expect(reported.failureType, FailureType.unexpectedFailure);
      final entry = _errors(io, p.join(claudeDir, 'logs')).single;
      expect(entry[LogEntryField.reason.name], redactedLogText);
    });

    test('a project that is not registered logs to the global log', () {
      final io = _io(registered: false);
      reportFailure(
        command: _command,
        error: StateError('boom'),
        projectRoot: _projectRoot,
        io: io,
      );
      expect(_errors(io, p.join(claudeDir, 'logs')), hasLength(1));
    });
  });
}
