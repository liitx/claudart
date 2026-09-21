import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../ui/render.dart' as render;

/// Removes the symlinks `link` creates: `.claude` and `.cursor/commands`.
///
/// Resolves the project root the same way `link` does — an explicit
/// override, else the git repository root — never the process cwd, so
/// running from a subdirectory still finds the project.
void runUnlink({FileIO? io, String? projectRootOverride}) {
  final fileIO = io ?? const RealFileIO();

  print(render.header('CLAUDART UNLINK'));

  final projectRoot = resolveProjectRoot(override: projectRootOverride);
  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project root.\n');
    return;
  }

  var removed = 0;

  for (final rel in ['.claude', p.join('.cursor', 'commands')]) {
    final path = p.join(projectRoot, rel);

    if (fileIO.linkExists(path)) {
      fileIO.deleteLink(path);
      print('✓ Removed symlink: $rel');
      removed++;
    } else if (fileIO.fileExists(path) || fileIO.dirExists(path)) {
      print('⚠  $rel exists but is not a symlink — skipped (not safe to delete)');
    }
  }

  if (removed == 0) {
    print('\nNo claudart symlinks found in $projectRoot');
  } else {
    print('\nProject directory is clean.\n');
  }
}
