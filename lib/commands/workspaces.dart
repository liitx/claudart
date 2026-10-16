// workspaces.dart — `claudart workspaces [--json]`: every linked workspace and
// the state of its session, for a human or an agent.
//
// Read-only apart from one line in the asking workspace's interactions log.
// Sessions are scoped to their own workspace; this is how an agent
// working in one learns that others exist and where they stand, so it can tell
// the user (or target one with `--project <name>`) instead of guessing. Never
// edit another workspace's handoff.md directly.

import 'dart:convert';
import 'dart:io';

import '../file_io.dart';
import '../git_utils.dart';
import '../logging/logger.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../session/workspace_guard.dart';
import '../workspace/workspace_link_state.dart';
import 'claudart_command.dart';

/// One linked workspace and where its session stands.
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.name,
    required this.projectRoot,
    required this.workspacePath,
    required this.status,
    required this.linkState,
    required this.locked,
    required this.lastSession,
    required this.isCurrent,
  });

  final String name;
  final String projectRoot;
  final String workspacePath;

  /// The status to show: [SessionState.effectiveStatus], so a blank handoff is
  /// [HandoffStatus.noHandoff].
  final HandoffStatus status;
  final WorkspaceLinkState linkState;

  /// An operation holds (or crashed holding) the workspace lock.
  final bool locked;
  final String lastSession;

  /// The workspace whose project root is the current directory.
  final bool isCurrent;

  bool get hasSession => status != HandoffStatus.noHandoff;

  Map<String, Object?> toJson() => {
        WorkspaceField.workspaceName.jsonKey: name,
        WorkspaceField.projectRoot.jsonKey: projectRoot,
        WorkspaceField.workspacePath.jsonKey: workspacePath,
        WorkspaceField.sessionStatus.jsonKey: status.name,
        WorkspaceField.hasSession.jsonKey: hasSession,
        WorkspaceField.linkState.jsonKey: linkState.name,
        WorkspaceField.locked.jsonKey: locked,
        WorkspaceField.lastSession.jsonKey: lastSession,
        WorkspaceField.isCurrent.jsonKey: isCurrent,
      };
}

/// The fields of [WorkspaceSummary.toJson]. The enum owns each key, so the
/// machine-readable shape is declared once and consumers can enumerate it.
enum WorkspaceField {
  workspaceName('name'),
  projectRoot('projectRoot'),
  workspacePath('workspacePath'),
  sessionStatus('status'),
  hasSession('hasSession'),
  linkState('linkState'),
  locked('locked'),
  lastSession('lastSession'),
  isCurrent('current');

  const WorkspaceField(this.jsonKey);

  final String jsonKey;
}

/// A column of the text listing; the enum owns its heading and its cell.
enum WorkspaceColumn {
  workspaceName('WORKSPACE'),
  sessionStatus('STATUS'),
  linkState('LINK'),
  lockState('LOCKED'),
  projectPath('PATH');

  const WorkspaceColumn(this.heading);

  final String heading;

  String cellOf(WorkspaceSummary summary) => switch (this) {
        WorkspaceColumn.workspaceName => summary.name,
        WorkspaceColumn.sessionStatus => summary.status.value,
        WorkspaceColumn.linkState => summary.linkState.name,
        WorkspaceColumn.lockState => summary.locked
            ? WorkspaceListingText.lockedCell
            : WorkspaceListingText.unlockedCell,
        WorkspaceColumn.projectPath => summary.projectRoot,
      };
}

/// The lone strings of the listing and of its JSON envelope.
abstract final class WorkspaceListingText {
  static const jsonRootKey = 'workspaces';
  static const currentMarker = '*';
  static const otherMarker = ' ';
  static const columnGap = '  ';
  static const lockedCell = 'yes';
  static const unlockedCell = 'no';
  static const emptyListing =
      'No linked workspaces. Run `claudart link` in a project to link one.';
  static const targetingHint =
      'Target another workspace: claudart --project <name> <command>. '
      "Never edit another workspace's handoff.md directly.";
}

String _markerOf(WorkspaceSummary summary) => summary.isCurrent
    ? WorkspaceListingText.currentMarker
    : WorkspaceListingText.otherMarker;

/// What an interaction with a workspace's session surface records as its
/// outcome in that workspace's interactions log.
enum WorkspaceInteraction {
  projectTargeted,
  workspacesListed;

  String outcomeFor({int workspaceCount = 0}) => switch (this) {
        WorkspaceInteraction.projectTargeted => 'targeted-by-project',
        WorkspaceInteraction.workspacesListed =>
          'listed $workspaceCount workspaces',
      };
}

/// A summary for every entry in [registry], sorted by name.
List<WorkspaceSummary> summarizeWorkspaces(
  Registry registry,
  FileIO io, {
  String? currentProjectRoot,
}) {
  final entries = registry.entries.toList()
    ..sort((left, right) => left.name.compareTo(right.name));
  return [
    for (final entry in entries)
      WorkspaceSummary(
        name: entry.name,
        projectRoot: entry.projectRoot,
        workspacePath: entry.workspacePath,
        status: _statusOf(entry.workspacePath, io),
        linkState: linkStateOf(io, entry.projectRoot),
        locked: isLocked(entry.workspacePath, io: io),
        lastSession: entry.lastSession,
        isCurrent: entry.projectRoot == currentProjectRoot,
      ),
  ];
}

HandoffStatus _statusOf(String workspacePath, FileIO io) {
  final file = handoffPathFor(workspacePath);
  return SessionState.parse(io.fileExists(file) ? io.read(file) : '')
      .effectiveStatus;
}

/// The listing as JSON (`{"workspaces": [...]}`) or an aligned text table.
String renderWorkspaces(
  List<WorkspaceSummary> summaries, {
  required bool asJson,
}) {
  if (asJson) {
    return const JsonEncoder.withIndent('  ').convert({
      WorkspaceListingText.jsonRootKey: [
        for (final summary in summaries) summary.toJson(),
      ],
    });
  }
  if (summaries.isEmpty) return WorkspaceListingText.emptyListing;
  final columnWidth = {
    for (final column in WorkspaceColumn.values)
      column: [
        column.heading.length,
        for (final summary in summaries) column.cellOf(summary).length,
      ].reduce((widest, width) => widest > width ? widest : width),
  };
  String line(String Function(WorkspaceColumn column) textOf) => [
        for (final column in WorkspaceColumn.values)
          textOf(column).padRight(columnWidth[column]!),
      ].join(WorkspaceListingText.columnGap).trimRight();
  const headerMarker = WorkspaceListingText.otherMarker;
  return [
    '$headerMarker ${line((column) => column.heading)}',
    for (final summary in summaries)
      '${_markerOf(summary)} ${line((column) => column.cellOf(summary))}',
    '',
    WorkspaceListingText.targetingHint,
  ].join('\n');
}

Future<void> runWorkspaces({
  FileIO? io,
  String? projectRootOverride,
  bool asJson = false,
  StringSink? listingSink,
}) async {
  final fileIO = io ?? const RealFileIO();
  final currentRoot = projectRootOverride ?? detectGitContext()?.root;
  final registry = Registry.load(io: fileIO);
  final summaries = summarizeWorkspaces(
    registry,
    fileIO,
    currentProjectRoot: currentRoot,
  );
  final currentSummary =
      summaries.where((summary) => summary.isCurrent).firstOrNull;
  if (currentSummary != null) {
    // Recorded in the asking workspace's log: what it was told about the rest.
    SessionLogger(io: fileIO, workspacePath: currentSummary.workspacePath)
        .logInteraction(
      command: ClaudartCommand.workspaces.wireName,
      outcome: WorkspaceInteraction.workspacesListed
          .outcomeFor(workspaceCount: summaries.length),
      platform: Platform.operatingSystem,
    );
  }
  (listingSink ?? stdout)
      .writeln(renderWorkspaces(summaries, asJson: asJson));
}
