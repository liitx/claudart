import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../handoff_template.dart';
import '../paths.dart';
import '../teardown_utils.dart';
import '../workspace/workspace_index.dart';
import 'archive_entry.dart';
import 'session_state.dart';

/// Archives the handoff content into the workspace archive directory.
void archiveHandoff(String workspace, String content, String branch,
    {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final dir = archiveDirFor(workspace);
  fileIO.createDir(dir);
  fileIO.write(p.join(dir, archiveName(branch)), content);
}

/// Snapshots the current handoff into the archive — file **and** index entry —
/// before it is overwritten, so "start fresh" never silently loses a prior
/// session. Returns the archive filename, or null when there is no handoff to
/// preserve. The filename is computed once so the written file and the index
/// entry always agree (archiveName is second-resolution and time-based).
String? archiveCurrentHandoff({
  required String workspace,
  FileIO? io,
  ArchiveKind kind = ArchiveKind.reminder,
  String? description,
}) {
  final fileIO = io ?? const RealFileIO();
  final handoffPath = handoffPathFor(workspace);
  if (!fileIO.fileExists(handoffPath)) return null;
  final content = fileIO.read(handoffPath);
  if (content.trim().isEmpty) return null;

  final state = SessionState.parse(content);
  final branch = state.branch;
  final baseName = archiveName(branch);
  final dir = archiveDirFor(workspace);
  var fileName = baseName;
  var suffix = 1;
  while (fileIO.fileExists(p.join(dir, fileName))) {
    fileName = '${p.basenameWithoutExtension(baseName)}_${suffix++}.md';
  }
  fileIO.createDir(dir);
  fileIO.write(p.join(dir, fileName), content);

  appendToIndex(
    workspace,
    ArchiveEntry(
      id:          p.basenameWithoutExtension(fileName),
      kind:        kind,
      description: state.bug.trim().isEmpty
          ? (description ?? 'session snapshot')
          : state.bug,
      branch:      branch,
      createdAt:   DateTime.now(),
      handoffFile: fileName,
    ),
    io: fileIO,
  );
  return fileName;
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
  } on Exception catch (e) {
    throw SessionCloseException('archive', cause: e);
  }

  // Step 2: reset handoff — rollback: delete archive.
  try {
    resetHandoff(workspace, io: fileIO);
  } on Exception catch (e) {
    _safeDelete(fileIO, archivePath);
    throw SessionCloseException('reset', cause: e);
  }

  // Step 3: remove symlink — rollback: restore handoff + delete archive.
  try {
    removeSessionLink(projectRoot, io: fileIO);
  } on Exception catch (e) {
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
