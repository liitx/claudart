import 'dart:io';
import '../io/file_io.dart';
import '../logging/logger.dart';
import '../logging/timed_source.dart';
import '../pipeline/model_observation.dart' show describeModelRecord;
import '../config/paths.dart';
import '../session/session_state.dart';
import '../session/skills_lookup.dart';
import '../session/teardown_utils.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../session/closure_evidence.dart';
import '../session/debug_disposition.dart';
import '../config/config.dart' show loadWorkspaceConfig;

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
    print(UserText.statusNoActiveHandoffRunClaudartSetup.template);
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
  printProjectLine(entry);
  print(UserText.statusBranch.format({'branch': currentBranch ?? state.branch}));
  final statusColour = render.statusColour(shown);
  print(UserText.statusLine.format({'status': ansi.c(statusColour, shown.value)}));
  if (state.hasActiveContent) {
    final closureEvidence = closureEvidenceOf(state);
    print(UserText.statusClosureLine.format({
      'evidence': closureEvidence.label,
      'closure': automaticClosureFor(closureEvidence).label,
    }));
    // A fix that was applied and analyzed but never verified, in a workspace
    // that names no verification command: say how to set one (gap R17).
    if (state.debugDisposition == DebugDisposition.done &&
        loadWorkspaceConfig(workspace, io: fileIO).verificationCommand == null) {
      print(UserText.statusVerificationHint
          .format({'configPath': configPathFor(workspace)}));
    }
  }
  print(UserText.statusBug.format({'text': _truncate(state.bug.text)}));
  print(UserText.statusRootCause.format({'text': _truncate(state.rootCause.text)}));
  if (shown == HandoffStatus.debugInProgress ||
      shown == HandoffStatus.needsSuggest) {
    print(UserText.statusUnresolved.format({'unresolved': _truncate(unresolved)}));
  }

  final skillsFile = skillsPathFor(workspace);
  if (!state.bug.isBlank &&
      fileIO.fileExists(skillsFile)) {
    final patterns =
        relevantSkillPatterns(fileIO.read(skillsFile), state.bug.text);
    if (patterns.isNotEmpty) {
      print(UserText.statusRelevantPastPatterns.template);
      for (final pattern in patterns) {
        print(UserText.indentedMaximum.format({'max': _truncate(pattern, max: 100)}));
      }
    }
  }

  if (currentBranch != null &&
      state.branch != 'unknown' &&
      currentBranch != state.branch) {
    final differs = UserText.statusBranchDiffers
        .format({'currentBranch': currentBranch, 'handoffBranch': state.branch});
    print(UserText.leadingBlankLine.format({'line': ansi.c(ansi.yellow, differs)}));
  }

  print('');
  print(UserText.statusHandoff.format({'handoffFile': handoffFile}));
  print(UserText.statusSkills.format({'workspace': skillsPathFor(workspace)}));

  final modelRecords =
      SessionLogger.plain(io: fileIO, workspacePath: workspace)
          .readStepModelRecords();
  if (modelRecords.isNotEmpty) {
    print(UserText.statusModelsNewestPerStep.template);
    for (final record in modelRecords) {
      print(UserText.statusModelRecordLine.format({'record': describeModelRecord(record)}));
    }
  }

  final timing = [
    for (final source in TimedSource.values)
      readTimedLog(fileIO, logsDirFor(workspace), source),
  ];
  final runs = summarizeTimed([
    for (final reading in timing)
      for (final record in reading.records)
        if (record.source == TimedSource.commandRun) record,
  ]);
  if (runs.isNotEmpty) {
    print(UserText.statusTimingHeading.template);
    for (final run in runs) {
      print(UserText.statusTimingLine.format({
        'label': run.label,
        'runs': '${run.runs}',
        'latest': '${run.latestMs}',
        'slowest': '${run.slowestMs}',
      }));
    }
  }
  final unreadable = timing.fold<int>(0, (sum, r) => sum + r.gaps.length);
  if (unreadable > 0) {
    print(UserText.statusTimingGaps.format({'count': '$unreadable'}));
  }

  print(UserText.nextStepHeading.template);
  print(UserText.statusNextStepLine.format({'nextStep': shown.nextStep}));
  print('');
}

String _truncate(String s, {int max = 80}) {
  final single = s.replaceAll('\n', ' ').trim();
  return single.length > max ? '${single.substring(0, max)}…' : single;
}

