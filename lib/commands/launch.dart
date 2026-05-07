import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart' show SessionState, HandoffStatus;
import '../session/workspace_guard.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import 'kill.dart';
import 'link.dart';
import 'setup.dart';

/// Interactive launcher — runs when `claudart` is invoked with no arguments.
///
/// Phase 1: loads registry only — shows project list before any workspace is opened.
/// Phase 2: loads workspace config and handoff only after the user selects a project.
Future<void> runLauncher({
  FileIO? io,
  String? projectRootOverride,
  int Function(List<String> items)? pickFn,
  bool Function(String question)? confirmFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final pick_ = pickFn ?? arrowMenu;

  print('\n═══════════════════════════════════════');
  print('  CLAUDART');
  print('═══════════════════════════════════════');

  // ── Phase 1: Registry load ─────────────────────────────────────────────────

  final registry = Registry.load(io: fileIO);
  final currentRoot = projectRootOverride ?? await (await detectGitContext())?.root;

  if (registry.isEmpty) {
    print('\nNo projects registered yet.');
    if (currentRoot != null) {
      print('  Current directory: $currentRoot');
      print('\nRun `claudart link` from your project to register it.\n');
    } else {
      print('\nNavigate to a project directory and run `claudart link`.\n');
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
    print('  Branch : ${state.branch}');
    final statusColour = _statusColour(state.status);
    print('  Status : ${ansi.c(statusColour, state.status.value)}');
    if (state.hasActiveContent) {
      print('  Bug    : ${_truncate(state.bug)}');
    }
  } else {
    print('  No active session.');
  }

  if (locked) {
    final op = interruptedOperation(workspace, io: fileIO) ?? 'unknown';
    print('  ${ansi.c(ansi.yellow, '⚠  Interrupted during: $op')}');
  }

  print('');

  // ── Action menu ───────────────────────────────────────────────────────────

  final int action;

  if (locked) {
    action = pick_([
      '${ansi.c(ansi.yellow, 'Kill')}   clear lock · archive · remove symlink',
      'Back',
    ]);
    if (action == LockedMenu.kill) {
      await runKill(
        io: fileIO,
        projectRootOverride: selected.projectRoot,
        confirmFn: confirmFn,
        exitFn: exitFn,
      );
    }
    return;
  }

  final hasActive = state != null && state.hasActiveContent;

  if (hasActive) {
    action = pick_([
      '${ansi.c(ansi.green, 'Resume')}  open editor · run /suggest or /debug',
      '${ansi.c(ansi.red, 'Kill')}    archive handoff · discard session',
      'Back',
    ]);
    if (action == ActiveMenu.resume) {
      _printResumeInstructions(state.status);
    } else if (action == ActiveMenu.kill) {
      await runKill(
        io: fileIO,
        projectRootOverride: selected.projectRoot,
        confirmFn: confirmFn,
        exitFn: exitFn,
      );
    }
  } else {
    action = pick_([
      (ansi.c(ansi.green, 'Start new session')),
      'Back',
    ]);
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

// ── Menu choice namespaces ─────────────────────────────────────────────────────
// 0-based. Exposed so tests reference named actions instead of magic numbers.

/// Locked-workspace menu choices.
abstract final class LockedMenu {
  static const kill = 0;
  static const back = 1;
}

/// Active-session menu choices.
abstract final class ActiveMenu {
  static const resume = 0;
  static const kill = 1;
  static const back = 2;
}

/// Fresh-workspace menu choices.
abstract final class FreshMenu {
  static const start = 0;
  static const back = 1;
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
    final linked = fileIO.linkExists(p.join(e.projectRoot, '.claude'));

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
      print('Open your editor and run /suggest to continue exploration.');
    case HandoffStatus.readyForSuggest:
      print('Ready for a new suggest cycle. Run /suggest to begin.');
    case HandoffStatus.readyForDebug:
      print('Root cause identified. Run /debug to implement the fix.');
    case HandoffStatus.debugInProgress:
      print('Fix in progress. Run /debug to continue.');
    case HandoffStatus.debugComplete:
      print('Debug complete. Run /save then verify with dart test.');
    case HandoffStatus.needsSuggest:
      print('Debug hit a blocker. Run /suggest for broader exploration.');
    case HandoffStatus.unknown || HandoffStatus.noHandoff:
      print('Run /suggest to begin or /debug if root cause is known.');
  }
  print('');
}

String _statusColour(HandoffStatus s) => switch (s) {
      HandoffStatus.suggestInvestigating ||
      HandoffStatus.readyForSuggest      => ansi.cyan,
      HandoffStatus.readyForDebug        => ansi.yellow,
      HandoffStatus.debugInProgress ||
      HandoffStatus.debugComplete        => ansi.green,
      HandoffStatus.needsSuggest         => ansi.red,
      HandoffStatus.unknown ||
      HandoffStatus.noHandoff            => ansi.dim,
    };

String _truncate(String s, {int max = 60}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
