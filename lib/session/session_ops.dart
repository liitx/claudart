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
/// Returns the filename written. Pass [archiveFileName] so a caller that
/// also needs the name (e.g. for rollback) uses the exact same one instead
/// of recomputing it from a second, possibly later, clock read.
String archiveHandoff(String workspace, String content, String branch,
    {FileIO? io, String? archiveFileName}) {
  final fileIO = io ?? const RealFileIO();
  final dir = archiveDirFor(workspace);
  fileIO.createDir(dir);
  final fileName = archiveFileName ?? archiveName(branch);
  fileIO.write(p.join(dir, fileName), content);
  return fileName;
}

/// Writes a handoff snapshot to archive/ **and** appends its index entry, in
/// one place, so every command that closes or archives a session — kill,
/// rotate, teardown — becomes visible to `claudart archives` instead of only
/// whichever one last remembered to call [appendToIndex]. Returns the entry
/// written, so a caller that needs to roll back a later step can remove it
/// again by id via [removeFromIndex].
ArchiveEntry writeArchiveEntry({
  required String workspace,
  required String branch,
  required String handoff,
  required ArchiveKind kind,
  required String description,
  FileIO? io,
  String? skillsDelta,
  String? archiveFileName,
  DateTime? now,
}) {
  final fileIO = io ?? const RealFileIO();
  final ts = now ?? DateTime.now();
  final fileName = archiveHandoff(workspace, handoff, branch,
      io: fileIO, archiveFileName: archiveFileName ?? archiveName(branch, now: ts));
  final entry = ArchiveEntry(
    id:          '${branch}_${ts.millisecondsSinceEpoch}',
    kind:        kind,
    description: description,
    branch:      branch,
    createdAt:   ts,
    handoffFile: fileName,
    skillsDelta: skillsDelta,
  );
  appendToIndex(workspace, entry, io: fileIO);
  return entry;
}

/// Snapshots the current handoff into the archive — file **and** index entry —
/// before it is overwritten, so "start fresh" never silently loses a prior
/// session. Returns the archive filename, or null when there is no handoff to
/// preserve.
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
  final entry = writeArchiveEntry(
    workspace:   workspace,
    branch:      state.branch,
    handoff:     content,
    kind:        kind,
    description: state.bug.trim().isEmpty
        ? (description ?? 'session snapshot')
        : state.bug,
    io: fileIO,
  );
  return entry.handoffFile;
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
  DateTime Function()? clock,
  ArchiveKind kind = ArchiveKind.reminder,
  String? description,
}) async {
  final fileIO = io ?? const RealFileIO();
  final handoffPath = handoffPathFor(workspace);
  final archiveDir = archiveDirFor(workspace);

  // Snapshot current handoff for rollback.
  final originalHandoff = fileIO.read(handoffPath);
  final branch = extractBranch(originalHandoff);
  final state = SessionState.parse(originalHandoff);
  // Computed once so the file archiveHandoff writes and the path rollback
  // deletes always agree, even across a second boundary.
  final now = clock?.call() ?? DateTime.now();
  final fileName = archiveName(branch, now: now);
  final archivePath = p.join(archiveDir, fileName);

  // Step 1: archive handoff + index entry — so kill becomes visible to
  // `claudart archives`, not just teardown.
  late final ArchiveEntry entry;
  try {
    entry = writeArchiveEntry(
      workspace:       workspace,
      branch:          branch,
      handoff:         originalHandoff,
      kind:            kind,
      description:     description ??
          (state.bug.trim().isEmpty ? 'session closed' : state.bug),
      io:              fileIO,
      archiveFileName: fileName,
      now:             now,
    );
  } on Exception catch (e) {
    throw SessionCloseException('archive', cause: e);
  }

  // Step 2: reset handoff — rollback: delete archive + index entry.
  try {
    resetHandoff(workspace, io: fileIO);
  } on Exception catch (e) {
    _safeDelete(fileIO, archivePath);
    removeFromIndex(workspace, entry.id, io: fileIO);
    throw SessionCloseException('reset', cause: e);
  }

  // Step 3: remove symlink — rollback: restore handoff + delete archive + index entry.
  try {
    removeSessionLink(projectRoot, io: fileIO);
  } on Exception catch (e) {
    _safeWrite(fileIO, handoffPath, originalHandoff);
    _safeDelete(fileIO, archivePath);
    removeFromIndex(workspace, entry.id, io: fileIO);
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
