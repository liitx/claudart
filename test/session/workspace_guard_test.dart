import 'package:test/test.dart';
import 'package:claudart/session/workspace_guard.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/errors/fault_class.dart';
import '../helpers/mocks.dart';

const _workspace = '/workspace/test-project';

void main() {
  group('isLocked', () {
    test('returns false when no lock file exists', () {
      final io = MemoryFileIO();
      expect(isLocked(_workspace, io: io), isFalse);
    });

    test('returns true when lock file exists', () {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): 'teardown'},
      );
      expect(isLocked(_workspace, io: io), isTrue);
    });
  });

  group('interruptedOperation', () {
    test('returns null when workspace is not locked', () {
      final io = MemoryFileIO();
      expect(interruptedOperation(_workspace, io: io), isNull);
    });

    test('returns operation name from lock file content', () {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): 'kill'},
      );
      expect(interruptedOperation(_workspace, io: io), equals('kill'));
    });

    test('returns "unknown" when lock file is empty', () {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): ''},
      );
      expect(interruptedOperation(_workspace, io: io), equals('unknown'));
    });
  });

  group('withGuard', () {
    test('throws WorkspaceLockedException if already locked', () async {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): 'setup'},
      );
      expect(
        () => withGuard(_workspace, 'teardown', () async {}, io: io),
        throwsA(isA<WorkspaceLockedException>()),
      );
    });

    test('WorkspaceLockedException carries the interrupted operation', () async {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): 'scan'},
      );
      try {
        await withGuard(_workspace, 'kill', () async {}, io: io);
        fail('expected exception');
      } on WorkspaceLockedException catch (e) {
        expect(e.interruptedOperation, equals('scan'));
        expect(e.failureType, equals(FailureType.workspaceLocked));
        // Overridden to transientFault, not workspace's default
        // environmentFault -- the lock clears itself once the other
        // session finishes, so retrying is the right response.
        expect(e.faultClass, equals(FaultClass.transientFault));
      }
    });

    test('creates lock file with operation name before fn runs', () async {
      final io = MemoryFileIO();
      String? lockDuringFn;

      await withGuard(_workspace, 'setup', () async {
        lockDuringFn = io.read(lockFilePath(_workspace)).trim();
      }, io: io);

      expect(lockDuringFn, equals('setup'));
    });

    test('removes lock file after successful operation', () async {
      final io = MemoryFileIO();
      await withGuard(_workspace, 'setup', () async {}, io: io);
      expect(isLocked(_workspace, io: io), isFalse);
    });

    test('leaves lock file when fn throws', () async {
      final io = MemoryFileIO();
      await expectLater(
        withGuard(
          _workspace,
          'teardown',
          () async => throw Exception('disk error'),
          io: io,
        ),
        throwsException,
      );
      expect(isLocked(_workspace, io: io), isTrue);
      expect(interruptedOperation(_workspace, io: io), equals('teardown'));
    });

    test('returns fn result on success', () async {
      final io = MemoryFileIO();
      final result = await withGuard(_workspace, 'setup', () async => 42, io: io);
      expect(result, equals(42));
    });
  });

  group('clearLock', () {
    test('removes lock file', () {
      final io = MemoryFileIO(
        files: {lockFilePath(_workspace): 'teardown'},
      );
      clearLock(_workspace, io: io);
      expect(isLocked(_workspace, io: io), isFalse);
    });

    test('is safe to call when no lock exists', () {
      final io = MemoryFileIO();
      expect(() => clearLock(_workspace, io: io), returnsNormally);
    });
  });
}
