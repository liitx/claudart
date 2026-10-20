import 'dart:async';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/archives.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/archive_entry.dart';
import 'package:claudart/workspace/workspace_index.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';
import '../helpers/project_fixture.dart';

const _projectRoot = ProjectFixture.root;
const _workspace   = ProjectFixture.workspace;

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

final _entryOne = ArchiveEntry(
  id: 'e1',
  kind: ArchiveKind.archive,
  description: 'fixed the flaky test',
  branch: 'main',
  createdAt: DateTime.utc(2026, 1, 1),
  handoffFile: 'handoff_e1.md',
  skillsDelta: 'learned: prefer real filesystems',
);

final _entryTwo = ArchiveEntry(
  id: 'e2',
  kind: ArchiveKind.reminder,
  description: 'paused mid-refactor',
  branch: 'wip/refactor',
  createdAt: DateTime.utc(2026, 1, 2),
  handoffFile: 'handoff_e2.md',
);

MemoryFileIO _io({List<ArchiveEntry> entries = const [], bool withSnapshots = true}) {
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
  for (final e in entries) {
    appendToIndex(_workspace, e, io: io);
    if (withSnapshots) {
      io.write(
        p.join(archiveDirFor(_workspace), e.handoffFile),
        '# snapshot for ${e.id}',
      );
    }
  }
  return io;
}

void main() {
  group('runArchives — validation', () {
    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO();
      await expectLater(
        runArchives(
          pickFn: unscriptedPick,
          
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 0 with no entries', () async {
      final io = _io();
      await expectLater(
        runArchives(
          pickFn: unscriptedPick,
          
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(0))),
      );
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      await expectLater(
        runZoned(
          () => runArchives(
            pickFn: unscriptedPick,
            
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(output.join('\n'), contains('Project  : my-app'));
    });
  });

  group('runArchives — selection menu', () {
    test('lists newest-first, cancel index is entries.length', () async {
      final io = _io(entries: [_entryOne, _entryTwo]);
      List<String>? capturedLabels;
      await expectLater(
        runArchives(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: (items) {
            capturedLabels = items;
            return items.length - 1; // cancel
          },
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(0))),
      );
      // Newest first: e2 (Jan 2) before e1 (Jan 1).
      expect(capturedLabels![0], contains('paused mid-refactor'));
      expect(capturedLabels![1], contains('fixed the flaky test'));
      expect(capturedLabels!.last, contains('Cancel'));
    });
  });

  group('runArchives — resume', () {
    test('restores the archived handoff to the active handoff path', () async {
      final io = _io(entries: [_entryOne]);
      var pickCall = 0;
      await runArchives(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        pickFn: (items) {
          pickCall++;
          return 0; // select the entry, then "Resume"
        },
      );
      expect(pickCall, equals(2));
      expect(io.read(handoffPathFor(_workspace)), equals('# snapshot for e1'));
    });

    test('reports a missing snapshot file instead of writing garbage', () async {
      final io = _io(entries: [_entryOne], withSnapshots: false);
      final output = <String>[];
      await runZoned(
        () => runArchives(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: (_) => 0,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(io.fileExists(handoffPathFor(_workspace)), isFalse);
      expect(output.join('\n'), contains('Snapshot file not found'));
      expect(output.join('\n'), isNot(contains('Handoff restored')));
    });
  });

  group('runArchives — view', () {
    test('does not modify the active handoff', () async {
      final io = _io(entries: [_entryOne]);
      var pickCall = 0;
      await runArchives(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        pickFn: (_) {
          pickCall++;
          return pickCall == 1 ? 0 : 1; // select entry, then "View snapshot"
        },
      );
      expect(io.fileExists(handoffPathFor(_workspace)), isFalse);
    });
  });
}
