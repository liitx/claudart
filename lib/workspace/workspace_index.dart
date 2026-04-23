// workspace_index.dart — read/write the archive/index.json for a workspace.
//
// The index is a JSON array of ArchiveEntry objects, appended at teardown.
// Commands read it to list or resume sessions.

import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../paths.dart';
import '../session/archive_entry.dart';

const _indexFile = 'index.json';

String _indexPath(String workspace) =>
    p.join(archiveDirFor(workspace), _indexFile);

/// Returns all archive entries for [workspace], newest first.
List<ArchiveEntry> loadIndex(String workspace, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final path   = _indexPath(workspace);
  if (!fileIO.fileExists(path)) return [];
  final raw = fileIO.read(path);
  final entries = archiveEntriesFromJson(raw);
  return entries.reversed.toList();
}

/// Appends [entry] to the index for [workspace].
void appendToIndex(String workspace, ArchiveEntry entry, {FileIO? io}) {
  final fileIO  = io ?? const RealFileIO();
  final dir     = archiveDirFor(workspace);
  fileIO.createDir(dir);
  final path    = _indexPath(workspace);
  final existing = fileIO.fileExists(path)
      ? archiveEntriesFromJson(fileIO.read(path))
      : <ArchiveEntry>[];
  existing.add(entry);
  fileIO.write(path, archiveEntriesToJson(existing));
}

/// Finds a single entry by [id], or null if not found.
ArchiveEntry? findEntry(String workspace, String id, {FileIO? io}) =>
    loadIndex(workspace, io: io).where((e) => e.id == id).firstOrNull;
