import 'dart:io';
import 'package:path/path.dart' as p;

// ── Filename constants ─────────────────────────────────────────────────────
// Single source of truth for all file/dir names used across claudart + consumers.

const String handoffFileName          = 'handoff.md';
const String skillsFileName           = 'skills.md';
const String archivesDirName          = 'archive';
const String archiveIndexFileName     = 'index.json';
const String flowCheckpointFileName   = 'flow_checkpoint.json';

/// Extracts the workspace directory from `claudart status` output.
/// Parses the `Handoff  : <path>/handoff.md` line and returns the parent dir.
/// Returns null if the expected pattern is not found.
String? parseWorkspaceDirFromStatusOutput(String output) {
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('Handoff') && trimmed.contains(':')) {
      final path = trimmed.split(':').sublist(1).join(':').trim();
      if (path.endsWith(handoffFileName)) return p.dirname(path);
    }
  }
  return null;
}

/// Root directory containing all project workspaces.
/// Resolved from CLAUDART_WORKSPACE env var, falls back to ~/.claudart/
final String workspacesRoot = () {
  final env = Platform.environment['CLAUDART_WORKSPACE'];
  if (env != null && env.isNotEmpty) {
    if (env.startsWith('~/')) {
      return p.join(Platform.environment['HOME']!, env.substring(2));
    }
    return env;
  }
  return p.join(Platform.environment['HOME']!, '.claudart');
}();

/// Registry of all known project workspaces.
String get registryPath => p.join(workspacesRoot, 'registry.json');

/// Returns the workspace directory for a named project.
String workspaceFor(String projectName) => p.join(workspacesRoot, projectName);

// ── Per-workspace path functions (new API) ─────────────────────────────────
// All take a resolved workspace path. Use with workspaceFor(name).

String handoffPathFor(String ws) => p.join(ws, 'handoff.md');
String skillsPathFor(String ws) => p.join(ws, 'skills.md');
String archiveDirFor(String ws) => p.join(ws, 'archive');
String configPathFor(String ws) => p.join(ws, 'config.json');
String knowledgeDirFor(String ws) => p.join(ws, 'knowledge');
String genericKnowledgeDirFor(String ws) => p.join(ws, 'knowledge', 'generic');
String projectsKnowledgeDirFor(String ws) => p.join(ws, 'knowledge', 'projects');
String claudeCommandsDirFor(String ws) => p.join(ws, '.claude', 'commands');
String tokenMapPathFor(String ws) => p.join(ws, 'token_map.json');
String logsDirFor(String ws) => p.join(ws, 'logs');
String experimentsDirFor(String ws) => p.join(ws, 'experiments');

// ── Legacy single-workspace paths ──────────────────────────────────────────
// Kept for backward compatibility while commands migrate to workspaceFor().
// TODO: remove once all callers use the per-workspace functions above.

/// @deprecated Use workspacesRoot directly.
String get claudeDir => workspacesRoot;

String get handoffPath           => handoffPathFor(workspacesRoot);
String get skillsPath            => skillsPathFor(workspacesRoot);
String get archiveDir            => archiveDirFor(workspacesRoot);
String get knowledgeDir          => knowledgeDirFor(workspacesRoot);
String get genericKnowledgeDir   => genericKnowledgeDirFor(workspacesRoot);
String get projectsKnowledgeDir  => projectsKnowledgeDirFor(workspacesRoot);
String get claudeCommandsDir     => claudeCommandsDirFor(workspacesRoot);
String get claudeMdPath          => p.join(workspacesRoot, 'CLAUDE.md');
