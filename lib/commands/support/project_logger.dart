// project_logger.dart — the logger a command's records go through, chosen once
//
// A registered project's records go to its own workspace logs, abstracted when
// the project is sensitive; a directory with no registered project writes to the
// global logs; a registry that cannot be read writes only what is recorded by
// type, because it cannot say whether the project is sensitive. The failure
// boundary and the run boundary both choose through here, so a command's run row
// and its failure land in the same logs.

import '../../io/file_io.dart';
import '../../io/git_utils.dart';
import '../../io/process_runner.dart';
import '../../logging/logger.dart';
import '../../registry.dart';

/// The logger for the project at [projectRoot], or at the git root when it is
/// null (asked of git through [runner]). Never throws for a missing or unreadable
/// registry.
SessionLogger loggerForProject({
  String? projectRoot,
  FileIO? io,
  ProcessRunner? runner,
}) {
  final fileIO = io ?? const RealFileIO();
  final root = projectRoot ?? detectGitContext(runner: runner)?.root;
  if (root == null) return SessionLogger.plain(io: fileIO);
  final RegistryEntry? entry;
  try {
    entry = Registry.load(io: fileIO).findByProjectRoot(root);
  } on CorruptRegistryException {
    return SessionLogger.labelOnly(io: fileIO);
  }
  return entry == null
      ? SessionLogger.plain(io: fileIO)
      : SessionLogger.forEntry(entry, io: fileIO);
}
