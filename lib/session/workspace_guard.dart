import 'package:path/path.dart' as p;
import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';
import '../file_io.dart';

const _lockFileName = 'workspace.lock';

/// Path to the lock file for a given workspace.
String lockFilePath(String workspacePath) =>
    p.join(workspacePath, _lockFileName);

/// Returns true if a lock file exists — workspace was interrupted or is active.
bool isLocked(String workspacePath, {FileIO? io}) =>
    (io ?? const RealFileIO()).fileExists(lockFilePath(workspacePath));

/// Returns the operation name recorded in the lock file, or null if not locked.
String? interruptedOperation(String workspacePath, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final lock = lockFilePath(workspacePath);
  if (!fileIO.fileExists(lock)) return null;
  final content = fileIO.read(lock).trim();
  return content.isEmpty ? 'unknown' : content;
}

/// Acquires a lock, runs [fn], then releases it.
///
/// If the workspace is already locked, throws [WorkspaceLockedException].
/// If [fn] throws, the lock is intentionally left in place — this marks
/// the workspace as interrupted so the user can recover on next startup.
Future<T> withGuard<T>(
  String workspacePath,
  String operationName,
  Future<T> Function() fn, {
  FileIO? io,
}) async {
  final fileIO = io ?? const RealFileIO();
  final lock = lockFilePath(workspacePath);

  if (fileIO.fileExists(lock)) {
    final op = fileIO.read(lock).trim();
    throw WorkspaceLockedException(
      workspacePath,
      op.isEmpty ? 'unknown' : op,
    );
  }

  fileIO.write(lock, operationName);
  try {
    final result = await fn();
    fileIO.delete(lock);
    return result;
  } catch (_) {
    // Lock left in place — signals interrupted state on next startup.
    rethrow;
  }
}

/// Clears a stale lock file — call only after confirming safe recovery.
void clearLock(String workspacePath, {FileIO? io}) =>
    (io ?? const RealFileIO()).delete(lockFilePath(workspacePath));

class WorkspaceLockedException extends ClaudartException {
  final String workspacePath;
  final String interruptedOperation;

  WorkspaceLockedException(this.workspacePath, this.interruptedOperation)
      : super(FailureType.workspaceLocked);

  @override
  String toString() =>
      'Workspace locked at $workspacePath '
      '(interrupted during: $interruptedOperation)';
}
