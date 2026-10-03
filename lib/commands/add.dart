// add.dart — claudart add wizard (PLAN.md Phase 3)
//
// Scaffolds a brand-new project workspace end to end: git author pre-fill,
// a short config questionnaire, PLAN.md/CLAUDE.md generation from Phase 2's
// templates, a registry entry, .claude/.cursor symlinking (reusing
// createProjectLinks — the same mechanism runLink uses), and registration
// in Claude Code's own auto-memory so a session started here already knows
// the project exists.
//
// Deliberately out of scope this phase (see PLAN.md's Phase 3 spec):
// CHANGELOG.md file generation, Mermaid diagram generation — both answers
// are recorded on the wizard's own answer set but not acted on.

import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../md_io.dart' show confirm;
import '../paths.dart';
import '../registry.dart';
import '../templates/claude_template.dart';
import '../templates/plan_template.dart';
import '../ui/line_editor.dart' as editor;
import '../ui/render.dart' as render;
import 'link.dart' show createProjectLinks;

/// Project shape — drives `claudeTemplate`'s optional Flutter constraint
/// line. Not named `WorkspaceConfig` — that name belongs to
/// `lib/workspace/workspace_config.dart`'s v2 per-project metadata class;
/// the former naming collision with `lib/config.dart`'s scan/sensitivity
/// settings was resolved by renaming the latter to `ProjectConfig`.
enum ProjectType {
  cli,
  library,
  tui,
  flutter;

  String get label => switch (this) {
        ProjectType.cli => 'cli',
        ProjectType.library => 'library',
        ProjectType.tui => 'tui',
        ProjectType.flutter => 'flutter',
      };
}

/// The wizard's answer set — collected once, then fed to every template.
/// `changelogEnabled`/`mermaidDiagrams` are recorded but not acted on this
/// phase (see file header).
typedef AddAnswers = ({
  String projectName,
  String? dartSdkConstraint,
  bool usesDartrix,
  bool githubTracking,
  bool mermaidDiagrams,
  bool changelogEnabled,
  ProjectType projectType,
});

/// Scaffolds a brand-new project workspace. See file header for the full
/// list of what this does and deliberately does not do.
Future<void> runAdd({
  FileIO? io,
  String? projectRootOverride,
  String? claudeMemoryRootOverride,
  String? Function(String question, {String? defaultValue})? promptFn,
  bool Function(String question)? confirmFn,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final prompt_ = promptFn ?? _defaultPrompt;
  final confirm_ = confirmFn ?? confirm;
  final exit_ = exitFn ?? exit;

  print(render.header('CLAUDART ADD'));

  // 1 — Detect project root.
  final projectRoot = projectRootOverride ?? detectGitContext()?.root;
  if (projectRoot == null) {
    print('\n✗ Not inside a git repository. Cannot detect project root.\n');
    exit_(1);
  }

  // 2 — Pre-fill from git: author, project name, pubspec.yaml content.
  final author = readGitAuthor(projectRoot);
  final defaultName = p.basename(projectRoot);
  final pubspecContent = fileIO.fileExists(p.join(projectRoot, 'pubspec.yaml'))
      ? fileIO.read(p.join(projectRoot, 'pubspec.yaml'))
      : '';
  final defaultSdk = _detectDartSdkConstraint(pubspecContent);
  final defaultUsesDartrix = _detectsDartrixDependency(pubspecContent);

  print('\n  Author  : ${author.name ?? '(not set)'} <${author.email ?? '(not set)'}>');

  // 3 — Questionnaire.
  final projectName = prompt_('Project name', defaultValue: defaultName) ?? defaultName;
  final sdkAnswer = prompt_('Dart SDK constraint', defaultValue: defaultSdk);
  final usesDartrix = defaultUsesDartrix || confirm_('Uses dartrix?');
  final githubTracking = confirm_('GitHub issue tracking?');
  final mermaidDiagrams = confirm_('Mermaid diagrams in PLAN.md?');
  final changelogEnabled = confirm_('CHANGELOG.md?');
  final projectTypeChoice = prompt_(
    'Project type (cli/library/tui/flutter)',
    defaultValue: ProjectType.cli.label,
  );
  final projectType = ProjectType.values
          .where((t) => t.label == projectTypeChoice)
          .firstOrNull ??
      ProjectType.cli;

  final answers = (
    projectName: projectName,
    dartSdkConstraint: sdkAnswer,
    usesDartrix: usesDartrix,
    githubTracking: githubTracking,
    mermaidDiagrams: mermaidDiagrams,
    changelogEnabled: changelogEnabled,
    projectType: projectType,
  );

  // 4 — Registry entry.
  final workspace = workspaceFor(answers.projectName);
  final today = DateTime.now().toIso8601String().split('T').first;
  var registry = Registry.load(io: fileIO);
  final entry = RegistryEntry(
    name: answers.projectName,
    projectRoot: projectRoot,
    workspacePath: workspace,
    createdAt: today,
    lastSession: today,
  );
  registry = registry.add(entry);
  registry.save(io: fileIO);

  // 5 — Workspace dirs, .claude/.cursor symlinks, command templates,
  // .gitignore — same mechanism runLink uses, shared not duplicated.
  final links = createProjectLinks(
    projectRoot: projectRoot,
    workspace: workspace,
    effectiveName: answers.projectName,
    fileIO: fileIO,
  );

  // 6 — Generate PLAN.md from scratch (a new workspace has none yet).
  final planPath = p.join(projectRoot, 'PLAN.md');
  fileIO.write(
    planPath,
    planStub(
      projectName: answers.projectName,
      usesDartrix: answers.usesDartrix,
      githubTracking: answers.githubTracking,
    ),
  );

  // 7 — Generate CLAUDE.md from scratch — never uses the marker-splice
  // path (that's runLink's step 9, re-run territory); a brand-new project
  // has nothing hand-maintained yet to preserve.
  final claudeMdPath = claudeMdPathFor(projectRoot);
  final claudeMdBody = claudeTemplate(
    workspacePath: workspace,
    projectName: answers.projectName,
    genericFiles: fileIO
        .listFiles(genericKnowledgeDirFor(workspace), extension: '.md')
        .map(p.basename)
        .toList()
      ..sort(),
    sdkConstraint: answers.dartSdkConstraint,
    flutterConstraint:
        answers.projectType == ProjectType.flutter ? answers.dartSdkConstraint : null,
  );
  fileIO.write(claudeMdPath, '# CLAUDE.md\n\n$claudeMdBody');

  // 8 — Archive scaffold: an empty `archive/` delta record, per PLAN.md's
  // "GitHub archive convention" — holds only content later removed from
  // main documents, never anything currently live.
  fileIO.write(p.join(projectRoot, 'archive', '.gitkeep'), '');
  fileIO.write(p.join(projectRoot, 'archive', 'README.md'), _archiveReadme);

  // 9 — Register in Claude Code's own auto-memory so a session started
  // here already knows the project exists.
  final memoryRoot = claudeMemoryRootOverride ??
      p.join(Platform.environment[homeEnvVar] ?? '', '.claude', 'projects');
  final projectHash = projectRoot.replaceAll('/', '-');
  final memoryDir = p.join(memoryRoot, projectHash, 'memory');
  fileIO.createDir(memoryDir);
  final memoryFilePath = p.join(memoryDir, 'project_${answers.projectName}.md');
  fileIO.write(memoryFilePath, _projectMemoryFile(answers, projectRoot, planPath));
  final memoryIndexPath = p.join(memoryDir, 'MEMORY.md');
  final existingIndex =
      fileIO.fileExists(memoryIndexPath) ? fileIO.read(memoryIndexPath) : '# Memory Index\n';
  final indexLine =
      '- [${answers.projectName}](project_${answers.projectName}.md) — scaffolded by `claudart add`';
  if (!existingIndex.contains(indexLine)) {
    fileIO.write(memoryIndexPath, '${existingIndex.trimRight()}\n$indexLine\n');
  }

  print('\n✓ Scaffolded: ${answers.projectName}');
  print('  PLAN.md   : $planPath');
  print('  CLAUDE.md : $claudeMdPath');
  print('  Workspace : $workspace');
  if (!links.symlinkSkipped) {
    print('  Symlink   : ${links.symlinkPath} → ${links.symlinkTarget}');
  }
  print('  Memory    : $memoryFilePath');
  print('\nRun `claudart setup` to begin a session.\n');
}

// ── pubspec.yaml detection — plain string/regex, no yaml package dep ────────

final RegExp _sdkConstraintPattern =
    RegExp('''sdk:\\s*['"]([^'"]+)['"]''');

String? _detectDartSdkConstraint(String pubspecContent) =>
    _sdkConstraintPattern.firstMatch(pubspecContent)?.group(1);

bool _detectsDartrixDependency(String pubspecContent) =>
    RegExp(r'^\s{2}dartrix:', multiLine: true).hasMatch(pubspecContent);

// ── Archive scaffold content ──────────────────────────────────────────────────

const String _archiveReadme = '''# archive/

This directory is a **delta record only** — it contains exclusively content
that has been removed from main documents. It never duplicates anything
currently in main.

> If the content still exists anywhere in any current document on main, it
> does not belong here. This directory only holds what main dropped.

See `PLAN.md`'s "GitHub archive convention" for the full entry format.
''';

// ── Memory file content ──────────────────────────────────────────────────────

String _projectMemoryFile(AddAnswers answers, String projectRoot, String planPath) => '''---
name: project-${answers.projectName}
description: ${answers.projectName} — scaffolded by claudart add, a ${answers.projectType.label} project at $projectRoot
metadata:
  type: project
---

${answers.projectName} was scaffolded by `claudart add`. Read `$planPath` first for
vision/architecture/roadmap — it is the authoritative document for this project.
''';

// ── Default injectables ──────────────────────────────────────────────────────

String? _defaultPrompt(String question, {String? defaultValue}) {
  final suffix = defaultValue != null ? ' [$defaultValue]' : '';
  stdout.write('\n$question$suffix\n');
  final input = editor.readLine(optional: true);
  return (input == null || input.isEmpty) ? defaultValue : input;
}

