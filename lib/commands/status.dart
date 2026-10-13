import 'dart:io';
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../session/skills_lookup.dart';
import '../session/teardown_utils.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;

Future<void> runStatus({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  bool prompt = false,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;

  final gitCtx = projectRootOverride != null ? null : detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;
  final currentBranch = gitCtx?.branch;

  if (projectRoot == null) {
    if (prompt) return; // silent in prompt mode — not in a registered project
    print('✗ Not inside a git repository. Cannot detect project.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    if (prompt) return; // silent in prompt mode
    print('✗ No claudart session found for this project.');
    print('  Run `claudart link` to register it.');
    exit_(1);
  }

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
  print('Bug      : ${_truncate(state.bug)}');
  print('Root cause: ${_truncate(state.rootCause)}');
  if (shown == HandoffStatus.debugInProgress ||
      shown == HandoffStatus.needsSuggest) {
    print('Unresolved: ${_truncate(unresolved)}');
  }

  final skillsFile = skillsPathFor(workspace);
  if (state.bug.isNotEmpty &&
      !state.bug.startsWith('_Not') &&
      fileIO.fileExists(skillsFile)) {
    final patterns = relevantSkillPatterns(fileIO.read(skillsFile), state.bug);
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

  print('\nNext step:');
  switch (shown) {
    case HandoffStatus.suggestInvestigating:
      print('  Run /suggest in your editor.');
    case HandoffStatus.readyForSuggest:
      print('  Run /suggest in your editor to begin a new cycle.');
    case HandoffStatus.readyForDebug:
      print('  Run /debug in your editor.');
    case HandoffStatus.debugInProgress:
      print('  Continue with /debug, or run /suggest if you hit a wall.');
    case HandoffStatus.debugComplete:
      print('  Verify with dart test, then claudart teardown.');
    case HandoffStatus.needsSuggest:
      print('  Run /suggest in your editor — debug has a question for you.');
    case HandoffStatus.unknown || HandoffStatus.noHandoff:
      print('  Run: claudart setup');
  }
  print('');
}

String _truncate(String s, {int max = 80}) {
  final single = s.replaceAll('\n', ' ').trim();
  return single.length > max ? '${single.substring(0, max)}…' : single;
}

