// workspace_index_test.dart — a corrupt index.json must never be silently
// treated as empty: that lets the next append overwrite it with one entry,
// destroying every prior record.

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/paths.dart';
import 'package:claudart/session/archive_entry.dart';
import 'package:claudart/workspace/workspace_index.dart';
import '../helpers/mocks.dart';

const _workspace = '/workspace/my-app';

String get _indexPath =>
    p.join(archiveDirFor(_workspace), archiveIndexFileName);

ArchiveEntry _entry(String id) => ArchiveEntry(
      id: id,
      kind: ArchiveKind.archive,
      description: 'd',
      branch: 'main',
      createdAt: DateTime(2026, 1, 1),
      handoffFile: 'handoff_main_2026-01-01.md',
    );

void main() {
  group('archiveEntriesFromJson — corrupt input', () {
    test('non-array JSON (a TypeError, not a FormatException) is not swallowed', () {
      // A JSON object at the top level decodes fine but `as List` throws a
      // TypeError, which the old code did not catch at all.
      expect(() => archiveEntriesFromJson('{"not": "a list"}'), throwsA(anything));
    });

    test('garbage text raises rather than silently returning empty', () {
      expect(() => archiveEntriesFromJson('not json at all'), throwsA(anything));
    });
  });

  group('appendToIndex — corrupt existing index', () {
    test('refuses to overwrite a corrupt index.json', () {
      final io = MemoryFileIO(files: {_indexPath: '{"oops": true}'});

      expect(
        () => appendToIndex(_workspace, _entry('a'), io: io),
        throwsA(anything),
      );

      // The garbage must still be there — not replaced by a one-entry array.
      expect(io.read(_indexPath), equals('{"oops": true}'));
    });

    test('refuses to overwrite index.json full of garbage text', () {
      final io = MemoryFileIO(files: {_indexPath: 'not json at all'});

      expect(
        () => appendToIndex(_workspace, _entry('a'), io: io),
        throwsA(anything),
      );

      expect(io.read(_indexPath), equals('not json at all'));
    });
  });

  group('appendToIndex — healthy index', () {
    test('still appends normally when the index is valid', () {
      final io = MemoryFileIO();
      appendToIndex(_workspace, _entry('a'), io: io);
      appendToIndex(_workspace, _entry('b'), io: io);
      final entries = loadIndex(_workspace, io: io);
      expect(entries, hasLength(2));
    });
  });
}
