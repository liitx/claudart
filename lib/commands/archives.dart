// archives.dart — `claudart archives` command
//
// Lists all archive entries for the current project workspace.
// Arrow-key navigation; actions: Resume (restore handoff) or View (print snapshot).
//
// Resume: copies the archived handoff.md back to the active handoff path,
// allowing the user to re-enter /suggest or /debug where they left off.

import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/archive_entry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../workspace/workspace_index.dart';

Future<void> runArchives({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  int Function(List<String> items)? pickFn,
}) async {
  final fileIO = io    ?? const RealFileIO();
  final exit_  = exitFn ?? exit;
  final pick_  = pickFn ?? arrowMenu;

  final projectRoot = projectRootOverride ?? await (await detectGitContext())?.root;
  if (projectRoot == null) {
    print('✗ Not inside a git repository.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry    = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('✗ Project not registered. Run `claudart link` first.');
    exit_(1);
  }

  final workspace = entry.workspacePath;
  final entries   = loadIndex(workspace, io: fileIO);

  if (entries.isEmpty) {
    print('\nNo archives found for this project.\n');
    exit_(0);
  }

  // ── Display list ───────────────────────────────────────────────────────────

  print('\n${ansi.bold}═══════════════════════════════════════${ansi.reset}');
  print('${ansi.bold}  CLAUDART ARCHIVES${ansi.reset}');
  print('${ansi.bold}═══════════════════════════════════════${ansi.reset}\n');

  final labels = entries.map((e) => _formatEntry(e)).toList();
  labels.add('${ansi.dim}Cancel${ansi.reset}');

  final chosen = pick_(labels);
  if (chosen >= entries.length) {
    print('\nCancelled.\n');
    exit_(0);
  }

  final selected = entries[chosen];

  // ── Action menu ────────────────────────────────────────────────────────────

  print('');
  final action = pick_(['Resume (restore handoff)', 'View snapshot', 'Cancel']);

  switch (action) {
    case 0:
      _resume(fileIO, workspace, selected);
      print(
        '\n${ansi.green}✓${ansi.reset}  Handoff restored from ${ansi.dim}${selected.handoffFile}${ansi.reset}\n'
        '  Next: open /suggest or /debug to continue.\n',
      );
    case 1:
      _view(fileIO, workspace, selected);
    case _:
      print('\nCancelled.\n');
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

void _resume(FileIO fileIO, String workspace, ArchiveEntry e) {
  final src  = p.join(archiveDirFor(workspace), e.handoffFile);
  final dest = handoffPathFor(workspace);
  if (!fileIO.fileExists(src)) {
    print('${ansi.red}✗${ansi.reset}  Snapshot file not found: $src');
    return;
  }
  fileIO.write(dest, fileIO.read(src));
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
