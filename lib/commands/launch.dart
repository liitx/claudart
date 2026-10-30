import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../io/git_utils.dart';
import '../config/paths.dart';
import '../registry.dart';
import '../session/session_state.dart' show SessionState, HandoffStatus;
import '../session/workspace_guard.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import 'kill.dart';
import 'link.dart';
import 'setup.dart';
import '../ui/render.dart' as render;
import '../workspace/workspace_link_state.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';

/// Interactive launcher — runs when `claudart` is invoked with no arguments.
///
/// Phase 1: loads registry only — shows project list before any workspace is opened.
/// Phase 2: loads workspace config and handoff only after the user selects a project.
Future<void> runLauncher({
  CommandSeams seams = const CommandSeams(),
}) async {
  final io = seams.io;
  final projectRootOverride = seams.projectRootOverride;
  final pickFn = seams.pickFn;
  final confirmFn = seams.confirmFn;
  final exitFn = seams.exitFn;
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final pick_ = pickFn ?? arrowMenu;

  print(render.header('CLAUDART'));

  // ── Phase 1: Registry load ─────────────────────────────────────────────────

  final registry = Registry.load(io: fileIO);
  final gitCtx = detectGitContext(workingDirectory: projectRootOverride);
  final currentRoot = projectRootOverride ?? gitCtx?.root;
  final currentBranch = gitCtx?.branch;

  if (registry.isEmpty) {
    print(UserText.launchNoProjectsRegisteredYet.template);
    if (currentRoot != null) {
      print(UserText.launchCurrentDirectory.format({'currentRoot': currentRoot}));
      print(UserText.launchRunClaudartLinkFromYourProject.template);
    } else {
      print(UserText.launchNavigateToAProjectDirectoryAnd.template);
    }
    exit_(0);
  }

  final currentEntry = currentRoot != null
      ? registry.findByProjectRoot(currentRoot)
      : null;

  final entries = registry.entries;
  final canRegister = currentRoot != null && currentEntry == null;

  print('');

  // Build project list items.
  final projectItems = _buildProjectItems(
    entries: entries,
    currentEntry: currentEntry,
    fileIO: fileIO,
    currentRoot: currentRoot,
    canRegister: canRegister,
  );

  final choice = pick_(projectItems);

  if (canRegister && choice == registerChoice(entries.length)) {
    await runLink(
      [],
      io: fileIO,
      projectRootOverride: projectRootOverride,
      confirmFn: confirmFn,
      exitFn: exitFn,
    );
    return;
  }

  final selected = entries[choice];

  // ── Phase 2: Workspace load ────────────────────────────────────────────────

  final workspace = selected.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final handoff =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';
  final state = handoff.isNotEmpty ? SessionState.parse(handoff) : null;
  final locked = isLocked(workspace, io: fileIO);

  final dashCount = (35 - selected.name.length).clamp(0, 35);
  print('\n─── ${selected.name} ${'─' * dashCount}');

  if (state != null) {
    final isCurrentProject =
        currentEntry != null && selected.workspacePath == currentEntry.workspacePath;
    final branch = (isCurrentProject ? currentBranch : null) ?? state.branch;
    print(UserText.killBranch.format({'branch': branch}));
    // A blank handoff is no-handoff, not its stale Status line.
    final shown = state.effectiveStatus;
    final statusColour = render.statusColour(shown);
    print('  Status : ${ansi.c(statusColour, shown.value)}');
    if (state.hasActiveContent) {
      print(UserText.killBug.format({'text': _truncate(state.bug.text)}));
    }
  } else {
    print(UserText.launchNoActiveSession.template);
  }

  if (locked) {
    final op = interruptedOperation(workspace, io: fileIO) ?? 'unknown';
    print('  ${ansi.c(ansi.yellow, '⚠  Interrupted during: $op')}');
  }

  print('');

  // ── Action menu ───────────────────────────────────────────────────────────

  if (locked) {
    final action = chooseFrom(LockedMenu.values, (m) => m.label, pick_);
    if (action == LockedMenu.kill) {
      await runKill(seams: seams.forProjectRoot(selected.projectRoot));
    }
    return;
  }

  final hasActive = state != null && state.hasActiveContent;

  if (hasActive) {
    final action = chooseFrom(ActiveMenu.values, (m) => m.label, pick_);
    switch (action) {
      case ActiveMenu.resume:
        _printResumeInstructions(state.status);
      case ActiveMenu.kill:
        await runKill(seams: seams.forProjectRoot(selected.projectRoot));
      case ActiveMenu.back:
        break;
    }
  } else {
    final action = chooseFrom(FreshMenu.values, (m) => m.label, pick_);
    if (action == FreshMenu.start) {
      await runSetup(projectRootOverride: selected.projectRoot);
    }
  }
}

/// Returns the 0-based index that maps to the Register action.
///
/// Exposed so tests can derive the correct pick index from registry size
/// rather than hard-coding a magic number.
int registerChoice(int entryCount) => entryCount;

// ── Menu choices ───────────────────────────────────────────────────────
// Each menu is an enum that owns its labels, in the order they are shown; a
// pick (an index) is turned back into the choice by [_choose], so no code
// compares an index to a number.

/// Locked-workspace menu choices.
enum LockedMenu {
  kill,
  back;

  String get label => switch (this) {
        kill => '${ansi.c(ansi.yellow, 'Kill')}   '
            'clear lock · archive · reset handoff',
        back => 'Back',
      };
}

/// Active-session menu choices.
enum ActiveMenu {
  resume,
  kill,
  back;

  String get label => switch (this) {
        resume => '${ansi.c(ansi.green, 'Resume')}  '
            'open editor · run /suggest or /debug',
        kill => '${ansi.c(ansi.red, 'Kill')}    '
            'archive handoff · discard session',
        back => 'Back',
      };
}

/// Fresh-workspace menu choices.
enum FreshMenu {
  start,
  back;

  String get label => switch (this) {
        start => ansi.c(ansi.green, 'Start new session'),
        back => 'Back',
      };
}

// ── Item builders ─────────────────────────────────────────────────────────────

List<String> _buildProjectItems({
  required List<RegistryEntry> entries,
  required RegistryEntry? currentEntry,
  required FileIO fileIO,
  required String? currentRoot,
  required bool canRegister,
}) {
  final items = <String>[];

  for (final e in entries) {
    final isCurrent = e == currentEntry;
    final locked = isLocked(e.workspacePath, io: fileIO);
    final linked = linkStateOf(fileIO, e.projectRoot).isLinked;

    final dot = locked
        ? ansi.c(ansi.yellow, '⚠')
        : linked
            ? ansi.c(ansi.green, '●')
            : ansi.c(ansi.dim, '○');

    final name = isCurrent ? ansi.c(ansi.bold, e.name) : e.name;
    final sensitive =
        e.sensitivityMode ? '  ${ansi.c(ansi.dim, '[sensitive]')}' : '';
    final warn = locked ? '  ${ansi.c(ansi.yellow, '⚠ interrupted')}' : '';

    items.add('$dot  $name   last: ${e.lastSession}$sensitive$warn');
  }

  if (canRegister && currentRoot != null) {
    items.add(ansi.c(ansi.cyan, '+  Register ${p.basename(currentRoot)}'));
  }

  return items;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void _printResumeInstructions(HandoffStatus status) {
  print('');
  switch (status) {
    case HandoffStatus.suggestInvestigating:
      print(UserText.launchOpenYourEditorAndRunSuggest.template);
    case HandoffStatus.readyForSuggest:
      print(UserText.launchReadyForANewSuggestCycle.template);
    case HandoffStatus.readyForDebug:
      print(UserText.launchRootCauseIdentifiedRunDebugTo.template);
    case HandoffStatus.debugInProgress:
      print(UserText.launchFixInProgressRunDebugTo.template);
    case HandoffStatus.debugComplete:
      print(UserText.launchDebugCompleteRunSaveThenVerify.template);
    case HandoffStatus.needsSuggest:
      print(UserText.launchDebugHitABlockerRunSuggest.template);
    case HandoffStatus.unknown || HandoffStatus.noHandoff:
      print(UserText.launchRunSuggestToBeginOrDebug.template);
  }
  print('');
}


String _truncate(String s, {int max = 60}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
