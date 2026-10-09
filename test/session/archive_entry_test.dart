// archive_entry_test.dart — archiveEntriesFromJson's parsing behavior.
//
// New file: lib/session/archive_entry.dart had no mirrored test file at
// all before this. ArchiveEntry.fromJson/toJson round-trips are already
// covered indirectly in workspace_index_test.dart/resume_test.dart/
// archives_test.dart -- scoped here to the one real gap found: nothing
// tested CorruptArchiveIndexException, anywhere, before this.

import 'package:test/test.dart';
import 'package:claudart/session/archive_entry.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/fault_class.dart';

void main() {
  group('archiveEntriesFromJson', () {
    test('returns an empty list for an empty string', () {
      expect(archiveEntriesFromJson(''), isEmpty);
    });

    test('throws CorruptArchiveIndexException for malformed JSON', () {
      expect(
        () => archiveEntriesFromJson('{ not json'),
        throwsA(
          isA<CorruptArchiveIndexException>()
              .having((e) => e.failureType, 'failureType', equals(FailureType.archiveIndexCorrupt))
              .having((e) => e.faultClass, 'faultClass', equals(FaultClass.environmentFault))
              .having((e) => e.cause, 'cause', isNotEmpty),
        ),
      );
    });

    test('throws CorruptArchiveIndexException for valid JSON of the wrong shape', () {
      // Valid JSON, but a map instead of a list -- the cast to
      // List<dynamic> throws a TypeError, not a FormatException.
      expect(
        () => archiveEntriesFromJson('{"not": "a list"}'),
        throwsA(isA<CorruptArchiveIndexException>()),
      );
    });

    test('parses a real, well-formed index', () {
      const json = '''
      [{"id": "a1", "kind": "archive", "description": "d", "branch": "main",
        "createdAt": "2026-01-01T00:00:00.000Z", "handoffFile": "h.md"}]
      ''';
      final entries = archiveEntriesFromJson(json);
      expect(entries, hasLength(1));
      expect(entries.first.id, 'a1');
    });
  });
}
