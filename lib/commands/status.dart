import 'dart:io';
import '../file_io.dart';
import '../logging/logger.dart';
import '../pipeline/model_observation.dart' show describeModelRecord;
import '../paths.dart';
import '../session/session_state.dart';
import '../session/skills_lookup.dart';
import '../session/teardown_utils.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import 'command_seams.dart';
import 'project_resolution.dart';

Future<void> runStatus({
  CommandSeams seams = const CommandSeams(),
  bool prompt = false,
}) async {
  final io = seams.io;
  final fileIO = io ?? const RealFileIO();

  // Silent in prompt mode — not in a registered project.
  final project = prompt
      ? lookupProject(seams, withGitContext: true)
      : requireProject(seams, withGitContext: true);
  if (project == null) return;
  final entry = project.entry;
  final currentBranch = project.gitContext?.branch;

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final content =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';

  if (content.isEmpty) {
    if (prompt) return;
    print('\nNo active handoff. Run: claudart setup\n');
    return;
  }

  final state = SessionState.parse(content);
  // What to show: a blank handoff is no-handoff, not its stale Status line.
  final shown = state.effectiveStatus;

  // ── Prompt mode: compact single-line output for shell RPROMPT/PS1 ──────────
  if (prompt) {
    stdout.write(render.statusBar(
      name: entry.name,
      statusLabel: shown.value,
      statusColorCode: render.statusColour(shown),
      active: shown.isPersisted,
    ));
    return;
  }

  final unresolved =
      readSubSection(extractSection(content, 'Debug Progress'),
          'What is still unresolved');

  print(render.header('CLAUDART SESSION STATUS'));
  print('Project  : ${entry.name}');
  print('Branch   : ${currentBranch ?? state.branch}');
  final statusColour = render.statusColour(shown);
  print('Status   : ${ansi.c(statusColour, shown.value)}');
  print('Bug      : ${_truncate(state.bug.text)}');
  print('Root cause: ${_truncate(state.rootCause.text)}');
  if (shown == HandoffStatus.debugInProgress ||
      shown == HandoffStatus.needsSuggest) {
    print('Unresolved: ${_truncate(unresolved)}');
  }

  final skillsFile = skillsPathFor(workspace);
  if (!state.bug.isBlank &&
      fileIO.fileExists(skillsFile)) {
    final patterns =
        relevantSkillPatterns(fileIO.read(skillsFile), state.bug.text);
    if (patterns.isNotEmpty) {
      print('\nRelevant past patterns:');
      for (final pattern in patterns) {
        print('  ${_truncate(pattern, max: 100)}');
      }
    }
  }

  if (currentBranch != null &&
      state.branch != 'unknown' &&
      currentBranch != state.branch) {
    print('\n${ansi.c(ansi.yellow, '⚠️  Current branch "$currentBranch" differs from handoff branch "${state.branch}".')}');
  }

  print('');
  print('Handoff  : $handoffFile');
  print('Skills   : ${skillsPathFor(workspace)}');

  final modelRecords =
      SessionLogger.plain(io: fileIO, workspacePath: workspace)
          .readStepModelRecords();
  if (modelRecords.isNotEmpty) {
    print('\nModels (newest per step):');
    for (final record in modelRecords) {
      print('  ${describeModelRecord(record)}');
    }
  }

  print('\nNext step:');
  print('  ${shown.nextStep}');
  print('');
}

String _truncate(String s, {int max = 80}) {
  final single = s.replaceAll('\n', ' ').trim();
  return single.length > max ? '${single.substring(0, max)}…' : single;
}

