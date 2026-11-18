// handoff_archive_test.dart — archiveCurrentHandoff: snapshot + index an
// existing handoff before it's overwritten; no-op when there's nothing to save.

import 'package:claudart/config/paths.dart';
import 'package:claudart/session/session_ops.dart';
import 'package:claudart/workspace/workspace_index.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

void main() {
  const ws = '/tmp/ws';
  final handoffPath = handoffPathFor(ws);

  const handoff = '''
## Status
ready-for-debug

## Bug
Label is null when not provided
''';

  group('archiveCurrentHandoff', () {
    test('snapshots the handoff to archive/ and appends an index entry', () {
      final io = MemoryFileIO(files: {handoffPath: handoff});

      final name = archiveCurrentHandoff(workspace: ws, io: io);

      expect(name, isNotNull);
      // The snapshot file is written under the workspace archive dir.
      expect(
        io.files.keys.any((k) => k.contains('/archive/') && k.endsWith(name!)),
        isTrue,
      );
      // It is indexed (so `claudart archives` can list/resume it), and the
      // index entry points at the file just written.
      final entries = loadIndex(ws, io: io);
      expect(entries, hasLength(1));
      expect(entries.first.handoffFile, equals(name));
    });

    test('returns null when there is no handoff', () {
      final io = MemoryFileIO();
      expect(archiveCurrentHandoff(workspace: ws, io: io), isNull);
    });

    test('returns null for a blank handoff', () {
      final io = MemoryFileIO(files: {handoffPath: '   \n'});
      expect(archiveCurrentHandoff(workspace: ws, io: io), isNull);
    });
  });
}
