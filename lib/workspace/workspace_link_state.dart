// workspace_link_state.dart — is this project linked to its claudart workspace?
//
// `claudart link` points the project's `.claude` at the workspace copy of the
// slash commands. It is normally a symlink; when link.dart cannot symlink, it
// falls back to a real directory (`symlinkSkipped`). Both mean "linked". The
// check used to be repeated by hand (launch.dart, kill.dart); this is the one
// typed reading of it.

import 'package:path/path.dart' as p;

import '../file_io.dart';
import '../paths.dart';

enum WorkspaceLinkState {
  /// No `.claude` at the project root: `claudart link` has not run (or
  /// `claudart unlink` removed it).
  unlinked,

  /// `.claude` is a symlink to the workspace copy: the normal case.
  symlinked,

  /// `.claude` is a real directory: link.dart could not create the symlink and
  /// fell back to a copy.
  realDirectory;

  bool get isLinked => this != unlinked;
}

/// Reads [projectRoot]'s link state from the filesystem.
WorkspaceLinkState linkStateOf(FileIO io, String projectRoot) {
  final claude = p.join(projectRoot, IdeIntegration.claudeCode.dirName);
  if (io.linkExists(claude)) return WorkspaceLinkState.symlinked;
  if (io.dirExists(claude)) return WorkspaceLinkState.realDirectory;
  return WorkspaceLinkState.unlinked;
}
