import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../io/git_utils.dart';
import '../config/paths.dart';
import '../ui/render.dart' as render;
import '../generated/user_text.g.dart';

/// Removes the symlinks `link` creates — `.claude` and `.cursor/commands` —
/// plus a legacy `CLAUDE.md` symlink from older claudart versions. Anything
/// that is not a symlink is left alone.
///
/// Resolves the project root the same way `link` does — an explicit
/// override, else the git repository root — never the process cwd, so
/// running from a subdirectory still finds the project.
void runUnlink({FileIO? io, String? projectRootOverride}) {
  final fileIO = io ?? const RealFileIO();

  print(render.header('CLAUDART UNLINK'));

  final projectRoot = resolveProjectRoot(override: projectRootOverride);
  if (projectRoot == null) {
    print(UserText.notInGitRepositoryRoot.template);
    return;
  }

  var removed = 0;

  for (final rel in [
    IdeIntegration.claudeCode.dirName,
    p.join(IdeIntegration.cursor.dirName, 'commands'),
    claudeMdFileName,
  ]) {
    final path = p.join(projectRoot, rel);

    if (fileIO.linkExists(path)) {
      fileIO.deleteLink(path);
      print(UserText.unlinkRemovedSymlink.format({'rel': rel}));
      removed++;
    } else if (fileIO.fileExists(path) || fileIO.dirExists(path)) {
      print(UserText.unlinkExistsButIsNotASymlink.format({'rel': rel}));
    }
  }

  if (removed == 0) {
    print(UserText.unlinkNoClaudartSymlinksFoundIn.format({'projectRoot': projectRoot}));
  } else {
    print(UserText.unlinkProjectDirectoryIsClean.template);
  }
}
