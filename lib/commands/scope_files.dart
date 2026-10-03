import '../config.dart';
import '../file_io.dart';
import '../md_io.dart';
import '../paths.dart';
import '../pipeline/pipeline_context.dart' show ScopeFile;

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
    print('\n⚠  Ignored ${parsed.rejected.length} scope path(s) outside the project root:');
    for (final path in parsed.rejected) {
      print('     - $path');
    }
    print('   To allow a location, add it to "allowedScopeRoots" in ${configPathFor(workspace)}.');
  }
  return parsed.accepted;
}
