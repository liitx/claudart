import 'dart:io';
import 'package:path/path.dart' as p;

/// Workspace directory — where all session files and knowledge live.
/// Resolved from CLAUDART_WORKSPACE env var, falls back to ~/.claudart/
final String claudeDir = () {
  final env = Platform.environment['CLAUDART_WORKSPACE'];
  if (env != null && env.isNotEmpty) {
    if (env.startsWith('~/')) {
      return p.join(Platform.environment['HOME']!, env.substring(2));
    }
    return env;
  }
  return p.join(Platform.environment['HOME']!, '.claudart');
}();

// Session state
final String handoffPath = p.join(claudeDir, 'handoff.md');
final String skillsPath  = p.join(claudeDir, 'skills.md');
final String archiveDir  = p.join(claudeDir, 'archive');

// Knowledge base
final String knowledgeDir        = p.join(claudeDir, 'knowledge');
final String genericKnowledgeDir = p.join(knowledgeDir, 'generic');
final String projectsKnowledgeDir = p.join(knowledgeDir, 'projects');

// Claude Code config (symlinked into projects at link time)
final String claudeCommandsDir = p.join(claudeDir, '.claude', 'commands');
final String claudeMdPath      = p.join(claudeDir, 'CLAUDE.md');
