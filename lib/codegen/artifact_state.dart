// artifact_state.dart — is a ClaudartArtifact's on-disk output still what
// its current source would produce?
//
// No persisted lock/hash file: every derivation (claudeTemplate,
// readmeTemplate, DependencyConfigCodegen.render, AgentFlow.commandTemplate)
// is already a pure render, so "stale" just means re-rendering from the
// current source and diffing against disk — the same comparison
// `_regenerateDependencyConfig` already makes before writing, generalized to
// the other 3 artifacts. `commandTemplates`' source (`AgentFlow.values`) is
// in-code, not a file, so this is a content diff, not an mtime check.

import 'package:path/path.dart' as p;

import '../dependency_config.dart';
import 'claudart_artifact.dart';
import 'dependency_config_codegen.dart';
import '../commands/link.dart' show generatedMarker, roadmapMarker;
import '../file_io.dart';
import '../paths.dart';
import '../pipeline/agent_flow.dart';
import '../templates/claude_template.dart';
import '../templates/readme_template.dart';

/// Whether a [ClaudartArtifact]'s on-disk output matches what its current
/// source would produce right now.
enum ArtifactState {
  /// On disk, and matches a fresh render of the current source.
  fresh,

  /// On disk, but a fresh render of the current source would differ.
  stale,

  /// This artifact is owned by claudart for this project but has no output
  /// on disk yet.
  missing,

  /// This artifact is opt-in (or has an unmet precondition) and this project
  /// hasn't opted in — not a defect.
  notApplicable,
}

/// Compares [artifact]'s on-disk output against a fresh render of its
/// current source. Read-only — never writes anything, unlike `runLink`'s own
/// regenerate step for the same artifact.
ArtifactState stateOf(
  ClaudartArtifact artifact, {
  required String projectRoot,
  required String workspace,
  required String projectName,
  required FileIO io,
}) => switch (artifact) {
      ClaudartArtifact.commandTemplates => _commandTemplatesState(
          projectRoot: projectRoot,
          workspace: workspace,
          projectName: projectName,
          io: io,
        ),
      ClaudartArtifact.claudeMdTail => _claudeMdTailState(
          projectRoot: projectRoot,
          workspace: workspace,
          projectName: projectName,
          io: io,
        ),
      ClaudartArtifact.readmeRoadmap =>
        _readmeRoadmapState(projectRoot: projectRoot, io: io),
      ClaudartArtifact.dependencyConfig =>
        _dependencyConfigState(projectRoot: projectRoot, io: io),
    };

ArtifactState _commandTemplatesState({
  required String projectRoot,
  required String workspace,
  required String projectName,
  required FileIO io,
}) {
  final commandsDir = claudeCommandsDirFor(workspace);
  for (final flow in AgentFlow.values.where((f) => f.hasCommandFile)) {
    final path = p.join(commandsDir, flow.fileName(projectName));
    if (!io.fileExists(path)) return ArtifactState.missing;
    final fresh = flow.commandTemplate(workspace, projectName);
    if (io.read(path) != fresh) return ArtifactState.stale;
  }
  return ArtifactState.fresh;
}

ArtifactState _claudeMdTailState({
  required String projectRoot,
  required String workspace,
  required String projectName,
  required FileIO io,
}) {
  final claudeMdPath = claudeMdPathFor(projectRoot);
  if (!io.fileExists(claudeMdPath)) return ArtifactState.missing;
  final existing = io.read(claudeMdPath);
  final match = generatedMarker.firstMatch(existing);
  if (match == null) return ArtifactState.missing;
  final genericFiles = io
      .listFiles(genericKnowledgeDir, extension: '.md')
      .map(p.basename)
      .toList()
    ..sort();
  final fresh = claudeTemplate(
    workspacePath: workspace,
    projectName: projectName,
    genericFiles: genericFiles,
  );
  return existing.substring(match.start) == fresh
      ? ArtifactState.fresh
      : ArtifactState.stale;
}

ArtifactState _readmeRoadmapState({
  required String projectRoot,
  required FileIO io,
}) {
  final roadmapJsonPath = p.join(projectRoot, 'roadmap.json');
  if (!io.fileExists(roadmapJsonPath)) return ArtifactState.notApplicable;
  final roadmapConfig = parseRoadmapConfig(io.read(roadmapJsonPath));
  if (roadmapConfig == null || roadmapConfig.rows.isEmpty) {
    return ArtifactState.notApplicable;
  }
  final readmePath = p.join(projectRoot, 'README.md');
  if (!io.fileExists(readmePath)) return ArtifactState.notApplicable;
  final existingReadme = io.read(readmePath);
  final match = roadmapMarker.firstMatch(existingReadme);
  if (match == null) return ArtifactState.notApplicable;
  final fresh = readmeTemplate(
    roadmapRows: roadmapConfig.rows,
    summaryText: roadmapConfig.summaryText ?? "What's coming",
    footerLine: roadmapConfig.footerLine,
  );
  // Compared the same way `_regenerateReadmeRoadmap` writes it: splice
  // `fresh` into the matched region and check whether that's a no-op.
  // A substring-equality check on the matched region alone is off by the
  // trailing newline `fresh` always carries but the match (bounded by the
  // `\n---` lookahead) never includes.
  final spliced = existingReadme.replaceRange(match.start, match.end, fresh);
  return spliced == existingReadme ? ArtifactState.fresh : ArtifactState.stale;
}

ArtifactState _dependencyConfigState({
  required String projectRoot,
  required FileIO io,
}) {
  final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
  if (!io.fileExists(pubspecPath)) return ArtifactState.notApplicable;
  final generatedPath =
      p.join(projectRoot, kDependencyConfigGeneratedRelativePath);
  if (!io.fileExists(generatedPath)) return ArtifactState.missing;
  const codegen = DependencyConfigCodegen();
  final fresh =
      codegen.render(usesDartrix: detectsDartrixDependency(io.read(pubspecPath)));
  return io.read(generatedPath) == fresh ? ArtifactState.fresh : ArtifactState.stale;
}
