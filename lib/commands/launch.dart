import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../session/workspace_guard.dart';
import 'kill.dart';
import 'link.dart';
import 'setup.dart';

// ANSI hyperlink: ESC]8;;url ESC\ text ESC]8;; ESC\
// Renders as a clickable link in terminals that support OSC 8.
const _readmeSensitivityUrl =
    'https://github.com/liitx/claudart#sensitivity-mode';

String _hyperlink(String text, String url) =>
    '\x1b]8;;$url\x1b\\$text\x1b]8;;\x1b\\';

/// Interactive launcher — runs when `claudart` is invoked with no arguments.
///
/// Phase 1: loads registry only — shows project list before any workspace is opened.
/// Phase 2: loads workspace config and handoff only after the user selects a project.
Future<void> runLauncher({
  FileIO? io,
  String? projectRootOverride,
  int Function(String prompt, int max)? pickFn,
  bool Function(String question)? confirmFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final pick_ = pickFn ?? _defaultPick;

  print('\n═══════════════════════════════════════');
  print('  CLAUDART');
  print('═══════════════════════════════════════');

  // ── Phase 1: Registry load ─────────────────────────────────────────────────

  final registry = Registry.load(io: fileIO);
  final currentRoot = projectRootOverride ?? detectGitContext()?.root;

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

  // Detect active project from current git root (if any).
  final currentEntry = currentRoot != null
      ? registry.findByProjectRoot(currentRoot)
      : null;

  final entries = registry.entries;
  final canRegister = currentRoot != null && currentEntry == null;

  // Print project list.
  print('');
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final isCurrent = e == currentEntry;
    final locked = isLocked(e.workspacePath, io: fileIO);
    final symlink = p.join(e.projectRoot, '.claude');
    final linked = fileIO.linkExists(symlink);

    final markers = [
      if (isCurrent) '(here)',
      if (linked) 'linked',
      if (locked) '⚠ interrupted',
      if (e.sensitivityMode)
        _hyperlink('[sensitive]', _readmeSensitivityUrl),
    ].join('  ');

    final label = '${i + 1}. ${e.name}';
    final meta = '  last: ${e.lastSession}';
    print('  $label$meta  $markers'.trimRight());
  }

  if (canRegister) {
    print('  ${entries.length + 1}. + Register ${p.basename(currentRoot)}');
  }

  print('');

  // ── User picks project ─────────────────────────────────────────────────────

  final maxChoice = entries.length + (canRegister ? 1 : 0);
  final choice = pick_('Select', maxChoice);

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

  final selected = entries[choice - 1];

  // ── Phase 2: Workspace load ────────────────────────────────────────────────

  final workspace = selected.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final handoff =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';
  final state = handoff.isNotEmpty ? SessionState.parse(handoff) : null;
  final locked = isLocked(workspace, io: fileIO);

  print('\n─── ${selected.name} ${'─' * (35 - selected.name.length).clamp(0, 35)}');
  if (state != null) {
    print('  Branch : ${state.branch}');
    print('  Status : ${state.status}');
    if (state.hasActiveContent) {
      print('  Bug    : ${_truncate(state.bug)}');
    }
  } else {
    print('  No active session.');
  }
  if (locked) {
    final op = interruptedOperation(workspace, io: fileIO) ?? 'unknown';
    print('  ⚠  Interrupted during: $op');
  }
  print('');

  // ── Action menu ───────────────────────────────────────────────────────────

  if (locked) {
    print('  1. Kill session  (clear lock, archive, remove symlink)');
    print('  2. Back\n');
    final action = pick_('Choose', 2);
    if (action == 1) {
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
    print('  1. Resume  (open editor and run /suggest or /debug)');
    print('  2. Kill    (archive handoff, discard session)');
    print('  3. Back\n');
    final action = pick_('Choose', 3);
    if (action == 1) {
      _printResumeInstructions(state.status);
    } else if (action == 2) {
      await runKill(
        io: fileIO,
        projectRootOverride: selected.projectRoot,
        confirmFn: confirmFn,
        exitFn: exitFn,
      );
    }
  } else {
    print('  1. Start new session');
    print('  2. Back\n');
    final action = pick_('Choose', 2);
    if (action == 1) {
      await runSetup(projectPath: selected.projectRoot);
    }
  }
}

/// Returns the menu choice number that maps to the Register action.
///
/// Exposed so tests can derive the correct pick index from registry size
/// rather than hard-coding a magic number.
int registerChoice(int entryCount) => entryCount + 1;

// ── Menu choice constants ─────────────────────────────────────────────────────
// Exposed so tests reference named actions instead of magic numbers.
// Each set maps to a specific context menu shown in Phase 2.

/// Locked-workspace menu: 1=Kill, 2=Back
const lockedMenuKill = 1;
const lockedMenuBack = 2;

/// Active-session menu: 1=Resume, 2=Kill, 3=Back
const activeMenuResume = 1;
const activeMenuKill = 2;
const activeMenuBack = 3;

/// Fresh-workspace menu: 1=Start new session, 2=Back
const freshMenuStart = 1;
const freshMenuBack = 2;

// ── Helpers ───────────────────────────────────────────────────────────────────

void _printResumeInstructions(String status) {
  print('');
  switch (status) {
    case 'suggest-investigating':
      print('Open your editor and run /suggest to continue exploration.');
    case 'ready-for-debug':
      print('Root cause identified. Run /debug to implement the fix.');
    case 'debug-in-progress':
      print('Fix in progress. Run /debug to continue.');
    case 'needs-suggest':
      print('Debug hit a blocker. Run /suggest for broader exploration.');
    default:
      print('Run /suggest to begin or /debug if root cause is known.');
  }
  print('');
}

String _truncate(String s, {int max = 60}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

int _defaultPick(String prompt, int max) {
  while (true) {
    stdout.write('$prompt (1–$max) > ');
    final input = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(input);
    if (n != null && n >= 1 && n <= max) return n;
    print('Enter a number between 1 and $max.');
  }
}
