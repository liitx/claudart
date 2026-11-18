import 'dart:io';
import 'dart:convert';

import 'package:claudart/commands/support/command_seams.dart';
import 'package:claudart/logging/recorded_outcome.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/io/process_exit.dart';
import 'package:claudart/commands/support/claudart_command.dart';
import 'package:claudart/commands/support/interaction_boundary.dart';
import 'package:claudart/commands/support/project_resolution.dart';
import 'package:claudart/registry.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

class _ExitCode implements Exception {
  _ExitCode(this.code);
  final int code;
}

const _root = '/projects/app';

MemoryFileIO _ioWithRegistry({required bool registered}) {
  final io = MemoryFileIO();
  if (registered) {
    Registry.load(io: io)
        .add(
          const RegistryEntry(
            name: 'app',
            projectRoot: _root,
            workspacePath: '/workspaces/app',
            createdAt: '2026-01-01',
            lastSession: '',
          ),
        )
        .save(io: io);
  }
  return io;
}

void main() {
  group('lookupProject', () {
    test('finds a registered project through the override', () {
      final project = lookupProject(
        CommandSeams(
          io: _ioWithRegistry(registered: true),
          projectRootOverride: _root,
        ),
      );
      expect(project?.entry.name, 'app');
      expect(project?.projectRoot, _root);
    });

    test('a project that is not registered is reported as such', () {
      ProjectLookupFailure? reported;
      final project = lookupProject(
        CommandSeams(
          io: _ioWithRegistry(registered: false),
          projectRootOverride: _root,
        ),
        onFailure: (found) => reported = found,
      );
      expect(project, isNull);
      expect(reported, ProjectLookupFailure.notRegistered);
    });

    test('outside any git repository is reported as such', () {
      final runner = MockProcessRunner();
      when(
        () => runner.runSync(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenReturn(ProcessResult(0, 128, '', 'fatal: not a git repository'));
      ProjectLookupFailure? reported;
      final project = lookupProject(
        CommandSeams(io: _ioWithRegistry(registered: true)),
        runner: runner,
        onFailure: (found) => reported = found,
      );
      expect(project, isNull);
      expect(reported, ProjectLookupFailure.notInGitRepository);
    });

    for (final failure in ProjectLookupFailure.values) {
      test('${failure.name} tells the user what happened', () {
        expect(failure.lines.first, startsWith('✗'));
      });
    }
  });

  group('requireProject names why it exits', () {
    Future<Map<String, dynamic>> exitRow({required bool registered}) async {
      final io = _ioWithRegistry(registered: registered);
      final logger = SessionLogger.plain(io: io, workspacePath: '/ws');
      try {
        await runRecorded(
          command: ClaudartCommand.status,
          logger: logger,
          leave: (code) => throw _ExitCode(code),
          body: () async => requireProject(
            CommandSeams(
              io: io,
              projectRootOverride: _root,
              exitFn: (code) =>
                  exitProcessWith(code, leave: (c) => throw _ExitCode(c)),
            ),
          ),
        );
      } on _ExitCode {
        // The exit is the point.
      }
      return jsonDecode(io
          .read(logFilePath('/ws/logs', LogFile.interactions))
          .trim()) as Map<String, dynamic>;
    }

    test('a project that is not registered is recorded as such', () async {
      final row = await exitRow(registered: false);
      expect(row['outcome'], RecordedOutcome.failed.name);
      expect(row['reason'], ProjectLookupFailure.notRegistered.name);
    });
  });

  group('requireProject', () {
    test('exits 1 when the project is not registered', () {
      expect(
        () => requireProject(
          CommandSeams(
            io: _ioWithRegistry(registered: false),
            projectRootOverride: _root,
            exitFn: (code) => throw _ExitCode(code),
          ),
        ),
        throwsA(isA<_ExitCode>().having((e) => e.code, 'code', 1)),
      );
    });

    test('returns the project when it is registered', () {
      final project = requireProject(
        CommandSeams(
          io: _ioWithRegistry(registered: true),
          projectRootOverride: _root,
          exitFn: (code) => throw _ExitCode(code),
        ),
      );
      expect(project.entry.workspacePath, '/workspaces/app');
    });
  });
}
