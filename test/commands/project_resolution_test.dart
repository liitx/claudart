import 'dart:io';

import 'package:claudart/commands/command_seams.dart';
import 'package:claudart/commands/project_resolution.dart';
import 'package:claudart/registry.dart';
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
          RegistryEntry(
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
      final original = Directory.current;
      final outside = Directory.systemTemp.createTempSync('no_git_');
      Directory.current = outside;
      try {
        ProjectLookupFailure? reported;
        final project = lookupProject(
          CommandSeams(io: _ioWithRegistry(registered: true)),
          onFailure: (found) => reported = found,
        );
        expect(project, isNull);
        expect(reported, ProjectLookupFailure.notInGitRepository);
      } finally {
        Directory.current = original;
        outside.deleteSync(recursive: true);
      }
    });

    for (final failure in ProjectLookupFailure.values) {
      test('${failure.name} tells the user what happened', () {
        expect(failure.lines.first, startsWith('✗'));
      });
    }
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
