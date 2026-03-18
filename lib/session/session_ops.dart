import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../handoff_template.dart';
import '../paths.dart';
import '../teardown_utils.dart';

/// Archives the handoff content into the workspace archive directory.
void archiveHandoff(String workspace, String content, String branch,
    {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final dir = archiveDirFor(workspace);
  fileIO.createDir(dir);
  fileIO.write(p.join(dir, archiveName(branch)), content);
}

/// Resets handoff.md to the blank template.
void resetHandoff(String workspace, {FileIO? io}) =>
    (io ?? const RealFileIO()).write(handoffPathFor(workspace), blankHandoff);

/// Removes the .claude symlink from the project directory.
void removeSessionLink(String projectRoot, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final link = p.join(projectRoot, '.claude');
  if (fileIO.linkExists(link)) fileIO.deleteLink(link);
}

/// Closes a session transactionally — archive → reset → remove symlink.
///
/// Each step rolls back prior steps on failure so the workspace is never
/// left in partial state. Callers are responsible for wrapping this in
/// [withGuard] from workspace_guard.dart.
///
/// Throws [SessionCloseException] describing which step failed.
Future<void> closeSession(
  String workspace,
  String projectRoot, {
  FileIO? io,
}) async {
  final fileIO = io ?? const RealFileIO();
  final handoffPath = handoffPathFor(workspace);
  final archiveDir = archiveDirFor(workspace);

  // Snapshot current handoff for rollback.
  final originalHandoff = fileIO.read(handoffPath);
  final branch = extractBranch(originalHandoff);
  final archivePath = p.join(archiveDir, archiveName(branch));

  // Step 1: archive handoff.
  try {
    archiveHandoff(workspace, originalHandoff, branch, io: fileIO);
  } catch (e) {
    throw SessionCloseException('archive', cause: e);
  }

  // Step 2: reset handoff — rollback: delete archive.
  try {
    resetHandoff(workspace, io: fileIO);
  } catch (e) {
    _safeDelete(fileIO, archivePath);
    throw SessionCloseException('reset', cause: e);
  }

  // Step 3: remove symlink — rollback: restore handoff + delete archive.
  try {
    removeSessionLink(projectRoot, io: fileIO);
  } catch (e) {
    _safeWrite(fileIO, handoffPath, originalHandoff);
    _safeDelete(fileIO, archivePath);
    throw SessionCloseException('unlink', cause: e);
  }
}

void _safeDelete(FileIO io, String path) {
  try {
    io.delete(path);
  } on FileSystemException catch (_) {}
}

void _safeWrite(FileIO io, String path, String content) {
  try {
    io.write(path, content);
  } on FileSystemException catch (_) {}
}

class SessionCloseException implements Exception {
  final String failedStep;
  final Object? cause;

  const SessionCloseException(this.failedStep, {this.cause});

  @override
  String toString() =>
      'Session close failed at step "$failedStep"'
      '${cause != null ? ': $cause' : ''}';
}
