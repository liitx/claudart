// archives.dart — `claudart archives` command
//
// Lists all archive entries for the current project workspace.
// Arrow-key navigation; actions: Resume (restore handoff) or View (print snapshot).
//
// Resume: copies the archived handoff.md back to the active handoff path,
// allowing the user to re-enter /suggest or /debug where they left off.

import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../config/paths.dart';
import '../session/archive_entry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../workspace/workspace_index.dart';
import '../ui/render.dart' as render;
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';

Future<void> runArchives({
  CommandSeams seams = const CommandSeams(),
}) async {
  final io = seams.io;
  final exitFn = seams.exitFn;
  final pickFn = seams.pickFn;
  final fileIO = io    ?? const RealFileIO();
  final exit_  = exitFn ?? exit;
  final pick_  = pickFn ?? arrowMenu;

  final project = requireProject(seams);
  final entry = project.entry;
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final entries   = loadIndex(workspace, io: fileIO);

  if (entries.isEmpty) {
    print(UserText.archivesNoArchivesFoundForThisProject.template);
    exit_(0);
  }

  // ── Display list ───────────────────────────────────────────────────────────

  print(render.header('CLAUDART ARCHIVES'));

  final labels = entries.map((e) => _formatEntry(e)).toList();
  labels.add('${ansi.dim}Cancel${ansi.reset}');

  final chosen = pick_(labels);
  if (chosen >= entries.length) {
    print(UserText.archivesCancelled.template);
    exit_(0);
  }

  final selected = entries[chosen];

  // ── Action menu ────────────────────────────────────────────────────────────

  print('');
  final action = pick_(['Resume (restore handoff)', 'View snapshot', 'Cancel']);

  switch (action) {
    case 0:
      if (_resume(fileIO, workspace, selected)) {
        print(
          '\n${ansi.green}✓${ansi.reset}  Handoff restored from ${ansi.dim}${selected.handoffFile}${ansi.reset}\n'
          '  Next: open /suggest or /debug to continue.\n',
        );
      }
    case 1:
      _view(fileIO, workspace, selected);
    case _:
      print(UserText.archivesCancelled.template);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatEntry(ArchiveEntry e) {
  final badge  = e.kind == ArchiveKind.reminder
      ? '${ansi.yellow}[reminder]${ansi.reset}'
      : '${ansi.cyan}[archive]${ansi.reset} ';
  final date   = e.createdAt.toIso8601String().split('T').first;
  final branch = ansi.dim + e.branch + ansi.reset;
  final desc   = e.description.length > 60
      ? '${e.description.substring(0, 60)}…'
      : e.description;
  return '$badge  $date  $branch  $desc';
}

/// Restores the archived handoff snapshot to the active handoff path.
/// Returns false (and prints an error) when the snapshot file is missing —
/// callers must not report success in that case.
bool _resume(FileIO fileIO, String workspace, ArchiveEntry e) {
  final src  = p.join(archiveDirFor(workspace), e.handoffFile);
  final dest = handoffPathFor(workspace);
  if (!fileIO.fileExists(src)) {
    print('${ansi.red}✗${ansi.reset}  Snapshot file not found: $src');
    return false;
  }
  fileIO.write(dest, fileIO.read(src));
  return true;
}

void _view(FileIO fileIO, String workspace, ArchiveEntry e) {
  final src = p.join(archiveDirFor(workspace), e.handoffFile);
  if (!fileIO.fileExists(src)) {
    print('${ansi.red}✗${ansi.reset}  Snapshot file not found: $src');
    return;
  }
  print('\n${ansi.dim}── ${e.handoffFile} ──${ansi.reset}\n');
  print(fileIO.read(src));
  if (e.skillsDelta != null) {
    print('\n${ansi.dim}── Skills delta ──${ansi.reset}');
    print(e.skillsDelta);
  }
  print('');
}
