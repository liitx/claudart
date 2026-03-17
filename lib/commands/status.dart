import 'dart:io';
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../teardown_utils.dart';

Future<void> runStatus({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;

  final gitCtx = projectRootOverride != null ? null : detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;
  final currentBranch = gitCtx?.branch;

  if (projectRoot == null) {
    print('✗ Not inside a git repository. Cannot detect project.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('✗ No claudart session found for this project.');
    print('  Run `claudart link` to register it.');
    exit_(1);
  }

  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final content =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';

  if (content.isEmpty) {
    print('\nNo active handoff. Run: claudart setup\n');
    return;
  }

  final state = SessionState.parse(content);
  final unresolved =
      readSubSection(extractSection(content, 'Debug Progress'),
          'What is still unresolved');

  print('\n═══════════════════════════════════════');
  print('  CLAUDART SESSION STATUS');
  print('═══════════════════════════════════════');
  print('Project  : ${entry.name}');
  print('Branch   : ${state.branch}');
  print('Status   : ${state.status.value}');
  print('Bug      : ${_truncate(state.bug)}');
  print('Root cause: ${_truncate(state.rootCause)}');
  if (state.status == HandoffStatus.debugInProgress ||
      state.status == HandoffStatus.needsSuggest) {
    print('Unresolved: ${_truncate(unresolved)}');
  }

  if (currentBranch != null &&
      state.branch != 'unknown' &&
      currentBranch != state.branch) {
    print('\n⚠  Current branch "$currentBranch" differs from handoff branch "${state.branch}".');
  }

  print('');
  print('Handoff  : $handoffFile');
  print('Skills   : ${skillsPathFor(workspace)}');

  print('\nNext step:');
  switch (state.status) {
    case HandoffStatus.suggestInvestigating:
      print('  Run /suggest in your editor.');
    case HandoffStatus.readyForDebug:
      print('  Run /debug in your editor.');
    case HandoffStatus.debugInProgress:
      print('  Continue with /debug, or run /suggest if you hit a wall.');
    case HandoffStatus.needsSuggest:
      print('  Run /suggest in your editor — debug has a question for you.');
    case HandoffStatus.unknown:
      print('  Run: claudart setup');
  }
  print('');
}

String _truncate(String s, {int max = 80}) {
  final single = s.replaceAll('\n', ' ').trim();
  return single.length > max ? '${single.substring(0, max)}…' : single;
}
