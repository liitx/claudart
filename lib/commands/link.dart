import 'dart:io';
import '../ui/line_editor.dart' as editor;
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import 'suggest_template.dart';
import 'debug_template.dart';
import 'save_template.dart';
import 'teardown_template.dart';

/// Registers the current project with claudart and creates the `.claude` symlink.
///
/// On first run: creates a per-project workspace, writes the registry entry,
/// and symlinks `<projectRoot>/.claude` → `<workspace>/.claude/`.
///
/// On re-run for an already-registered project: updates sensitivity mode and
/// recreates the symlink if missing.
Future<void> runLink(
  List<String> args, {
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final confirm_ = confirmFn ?? _defaultConfirm;
  final exit_ = exitFn ?? exit;

  print('\n═══════════════════════════════════════');
  print('  CLAUDART LINK');
  print('═══════════════════════════════════════');

  // 1 — Detect project root.
  final projectRoot = projectRootOverride ?? detectGitContext()?.root;
  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project root.\n');
    exit_(1);
  }

  // 2 — Resolve project name: arg > git remote > directory name.
  final projectName = args.isNotEmpty
      ? args.first
      : (projectRootOverride != null
          ? p.basename(projectRootOverride)
          : _detectProjectName(projectRoot));

  print('\n  Project : $projectName');
  print('  Root    : $projectRoot');

  // 3 — Load registry and check for existing entry.
  var registry = Registry.load(io: fileIO);
  final existing = registry.findByProjectRoot(projectRoot);

  if (existing != null && existing.name != projectName) {
    print('\n⚠  This project is already registered as "${existing.name}".');
    print('   Re-linking under the same name.');
  }

  final effectiveName = existing?.name ?? projectName;
  final workspace = workspaceFor(effectiveName);

  // 4 — Create workspace directory and .claude commands subdir.
  fileIO.createDir(workspace);
  fileIO.createDir(p.join(workspace, '.claude', 'commands'));

  // 5 — Sensitivity mode.
  final currentSensitivity = existing?.sensitivityMode ?? false;
  bool sensitivityMode;

  if (existing != null) {
    print('\n  Sensitivity mode is currently: '
        '${currentSensitivity ? 'ON' : 'OFF'}');
    if (confirm_('Change sensitivity mode?')) {
      sensitivityMode = confirm_('Enable sensitivity mode?');
    } else {
      sensitivityMode = currentSensitivity;
    }
  } else {
    sensitivityMode = confirm_('Enable sensitivity mode?');
  }

  // 6 — Write or update registry entry.
  final today = DateTime.now().toIso8601String().split('T').first;
  final entry = RegistryEntry(
    name: effectiveName,
    projectRoot: projectRoot,
    workspacePath: workspace,
    createdAt: existing?.createdAt ?? today,
    lastSession: existing?.lastSession ?? today,
    sensitivityMode: sensitivityMode,
  );
  registry = registry.add(entry);
  registry.save(io: fileIO);

  // 7 — Create .claude symlink: <projectRoot>/.claude → <workspace>/.claude/
  final symlinkPath = p.join(projectRoot, '.claude');
  final symlinkTarget = p.join(workspace, '.claude');

  if (fileIO.linkExists(symlinkPath)) {
    print('\n⚠  Removing existing .claude symlink.');
    fileIO.deleteLink(symlinkPath);
  }

  final symlinkSkipped = fileIO.dirExists(symlinkPath);
  if (symlinkSkipped) {
    print('\n⚠  .claude/ is a real directory — symlink skipped.');
    print('  Slash commands in .claude/commands/ are already available.');
  } else {
    fileIO.createLink(symlinkPath, symlinkTarget);
  }

  // 7b — Write suggest/debug/save templates to workspace .claude/commands/.
  // Always written so the workspace stays in sync regardless of symlink state.
  final workspaceCmdsDir = p.join(workspace, '.claude', 'commands');
  fileIO.write(p.join(workspaceCmdsDir, 'suggest.md'),
      suggestCommandTemplate(workspace));
  fileIO.write(p.join(workspaceCmdsDir, 'debug.md'),
      debugCommandTemplate(workspace));
  fileIO.write(p.join(workspaceCmdsDir, 'save.md'),
      saveCommandTemplate(workspace));
  fileIO.write(p.join(workspaceCmdsDir, 'teardown.md'),
      teardownCommandTemplate(workspace));

  // 8 — Auto-add .claude to .gitignore (only when a symlink was created).
  // When .claude/ is a real tracked directory, do not gitignore it.
  if (!symlinkSkipped) _ensureGitignore(projectRoot, fileIO);

  print('\n✓ Registered: $effectiveName');
  print('  Workspace : $workspace');
  if (symlinkSkipped) {
    print('  Commands  : .claude/commands/ (source directory, no symlink needed)');
  } else {
    print('  Symlink   : $symlinkPath → $symlinkTarget');
  }
  if (sensitivityMode) print('  Sensitivity mode: ON');
  print('\nRun `claudart setup` to begin a session.\n');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void _ensureGitignore(String projectRoot, FileIO fileIO) {
  final path = p.join(projectRoot, '.gitignore');
  final current = fileIO.read(path);
  final lines = current.split('\n');
  if (lines.any((l) => l.trim() == '.claude')) return;
  final updated = current.isEmpty
      ? '.claude\n'
      : '${current.trimRight()}\n.claude\n';
  fileIO.write(path, updated);
  print('  .gitignore: added .claude');
}

bool _defaultConfirm(String question) {
  stdout.write('\n$question [y/n]\n');
  final input = editor.readLine(optional: true);
  return input?.toLowerCase() == 'y' || input?.toLowerCase() == 'yes';
}

String _detectProjectName(String projectRoot) {
  try {
    final result = Process.runSync(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: projectRoot,
    );
    if (result.exitCode == 0) {
      final url = (result.stdout as String).trim();
      if (url.isNotEmpty) {
        final name = url.split('/').last.replaceAll('.git', '').trim();
        if (name.isNotEmpty) return name;
      }
    }
  } on Exception catch (_) {}
  return p.basename(projectRoot);
}
