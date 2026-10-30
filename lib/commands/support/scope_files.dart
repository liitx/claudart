import '../../config/config.dart';
import '../../io/file_io.dart';
import '../../session/md_io.dart';
import '../../config/paths.dart';
import '../../pipeline/pipeline_context.dart' show ScopeFile;
import '../../generated/user_text.g.dart';

/// Reads the handoff's `### Files in play`, applying the workspace's
/// `allowedScopeRoots` containment, and tells the user about any path that was
/// dropped for leaving the project instead of ignoring it silently.
List<ScopeFile> readScopeFiles({
  required String scope,
  required String projectRoot,
  required String workspace,
  FileIO? io,
}) {
  final config = loadWorkspaceConfig(workspace, io: io);
  final parsed = parseScopeFilesChecked(scope, projectRoot, allowedRoots: config.allowedScopeRoots);
  if (parsed.rejected.isNotEmpty) {
    print(UserText.scopeFilesIgnoredScopePathSOutsideThe.format({'length': parsed.rejected.length}));
    for (final path in parsed.rejected) {
      print(UserText.scopePathBullet.format({'path': path}));
    }
    print(UserText.scopeFilesToAllowALocationAddIt.format({'workspace': configPathFor(workspace)}));
  }
  return parsed.accepted;
}
