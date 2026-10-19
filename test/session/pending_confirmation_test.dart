import 'dart:io' show FileSystemException;

import 'package:test/test.dart';
import 'package:claudart/file_io.dart';
import 'package:claudart/session/pending_confirmation.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _workspace = '/workspace/my-app';

/// A FileIO whose read() throws — simulates a real IO error (e.g. the file
/// existed when fileExists() was checked but became unreadable before the
/// read, a genuine TOCTOU race, not a hypothetical).
class _ThrowsOnReadFileIO implements FileIO {
  const _ThrowsOnReadFileIO();

  @override
  bool fileExists(String path) => true;

  @override
  String read(String path) => throw const FileSystemException('simulated IO error');

  @override
  void write(String path, String content) => throw UnimplementedError();
  @override
  void append(String path, String content) => throw UnimplementedError();
  @override
  T withExclusiveLock<T>(String path, T Function() body) =>
      throw UnimplementedError();
  @override
  void delete(String path) => throw UnimplementedError();
  @override
  bool dirExists(String path) => throw UnimplementedError();
  @override
  void createDir(String path) => throw UnimplementedError();
  @override
  List<String> listFiles(String dirPath, {String? extension}) => throw UnimplementedError();
  @override
  bool linkExists(String path) => throw UnimplementedError();
  @override
  void deleteLink(String path) => throw UnimplementedError();
  @override
  void createLink(String linkPath, String targetPath) => throw UnimplementedError();
}

void main() {
  group('PendingConfirmation — JSON round-trip', () {
    test('toJson/fromJson preserves all fields', () {
      final createdAt = DateTime.utc(2026, 9, 20, 22, 0, 0);
      final confirmation = PendingConfirmation(
        question: 'Does this reflect the current confirmed state?',
        onConfirmCommand: 'claudart save',
        createdAt: createdAt,
      );

      final roundTripped = PendingConfirmation.fromJson(confirmation.toJson());

      expect(roundTripped.question, equals(confirmation.question));
      expect(roundTripped.onConfirmCommand, equals(confirmation.onConfirmCommand));
      expect(roundTripped.createdAt, equals(confirmation.createdAt));
    });

    test('normalizes a local-time createdAt to UTC on both write and read '
        '— durable state must be timezone-unambiguous regardless of which '
        'consumer wrote or reads it', () {
      final localCreatedAt = DateTime(2026, 9, 20, 22, 0, 0);
      final confirmation = PendingConfirmation(
        question: 'q',
        onConfirmCommand: 'claudart save',
        createdAt: localCreatedAt,
      );

      final json = confirmation.toJson();
      expect(json['createdAt'], endsWith('Z'));

      final roundTripped = PendingConfirmation.fromJson(json);
      expect(roundTripped.createdAt.isUtc, isTrue);
      expect(roundTripped.createdAt, equals(localCreatedAt.toUtc()));
    });
  });

  group('PendingConfirmationStore.load', () {
    test('returns null when file does not exist', () {
      final io = MemoryFileIO();
      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('returns null when file is empty', () {
      final io = MemoryFileIO();
      io.write(pendingConfirmationPathFor(_workspace), '');
      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('returns null when file is corrupt JSON', () {
      final io = MemoryFileIO();
      io.write(pendingConfirmationPathFor(_workspace), '{not valid json');
      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('returns null when a required field is missing', () {
      final io = MemoryFileIO();
      io.write(pendingConfirmationPathFor(_workspace), '{"question": "only this"}');
      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
    });

    test('never throws — a real IO error on read() resolves to null, not '
        'an uncaught exception (the file existed at the fileExists() '
        'check but became unreadable before the read — a genuine race, '
        'not hypothetical)', () {
      expect(
        () => PendingConfirmationStore.load(_workspace, io: const _ThrowsOnReadFileIO()),
        returnsNormally,
      );
      expect(
        PendingConfirmationStore.load(_workspace, io: const _ThrowsOnReadFileIO()),
        isNull,
      );
    });

    test('returns the written confirmation', () {
      final io = MemoryFileIO();
      final confirmation = PendingConfirmation(
        question: 'Ready to write this fix?',
        onConfirmCommand: 'claudart debug',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      PendingConfirmationStore.write(_workspace, confirmation, io: io);

      final loaded = PendingConfirmationStore.load(_workspace, io: io);

      expect(loaded, isNotNull);
      expect(loaded!.question, equals(confirmation.question));
      expect(loaded.onConfirmCommand, equals(confirmation.onConfirmCommand));
    });
  });

  group('PendingConfirmationStore.write', () {
    test('overwrites an existing pending confirmation', () {
      final io = MemoryFileIO();
      PendingConfirmationStore.write(
        _workspace,
        PendingConfirmation(
          question: 'first',
          onConfirmCommand: 'claudart save',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        io: io,
      );
      PendingConfirmationStore.write(
        _workspace,
        PendingConfirmation(
          question: 'second',
          onConfirmCommand: 'claudart debug',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
        io: io,
      );

      final loaded = PendingConfirmationStore.load(_workspace, io: io);
      expect(loaded!.question, equals('second'));
      expect(loaded.onConfirmCommand, equals('claudart debug'));
    });
  });

  group('PendingConfirmationStore.clear', () {
    test('removes an existing pending confirmation', () {
      final io = MemoryFileIO();
      PendingConfirmationStore.write(
        _workspace,
        PendingConfirmation(
          question: 'q',
          onConfirmCommand: 'claudart save',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        io: io,
      );

      PendingConfirmationStore.clear(_workspace, io: io);

      expect(PendingConfirmationStore.load(_workspace, io: io), isNull);
      expect(io.fileExists(pendingConfirmationPathFor(_workspace)), isFalse);
    });

    test('is a no-op when nothing is pending', () {
      final io = MemoryFileIO();
      expect(
        () => PendingConfirmationStore.clear(_workspace, io: io),
        returnsNormally,
      );
    });
  });
}
