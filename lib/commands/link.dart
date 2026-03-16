import 'dart:io';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../md_io.dart';
import '../paths.dart';
import '../knowledge_templates.dart';
import '../pubspec_utils.dart';

Future<void> runLink(List<String> args) async {
  final projectName = args.isNotEmpty ? args.first : _detectProjectName();

  print('\n═══════════════════════════════════════');
  print('  CLAUDART LINK: $projectName');
  print('═══════════════════════════════════════');

  // Verify workspace is initialized
  if (!Directory(genericKnowledgeDir).existsSync()) {
    print('\n✗ Workspace not initialized. Run `claudart init` first.\n');
    exit(1);
  }

  // Verify project knowledge file exists
  final projectFile = p.join(projectsKnowledgeDir, '$projectName.md');
  if (!File(projectFile).existsSync()) {
    print('\n✗ No knowledge file found for "$projectName".');
    print('  Run: claudart init --project $projectName\n');
    exit(1);
  }

  final cwd = Directory.current.path;
  final claudeLinkPath = p.join(cwd, '.claude');
  final claudeMdLinkPath = p.join(cwd, 'CLAUDE.md');

  // Check for existing symlinks or real files
  _checkExisting(claudeLinkPath, '.claude');
  _checkExisting(claudeMdLinkPath, 'CLAUDE.md');

  // Read project SDK constraints from its pubspec.yaml
  final env = readProjectEnv(cwd);
  if (env.sdk != null) {
    print('\n📦 Detected SDK constraint: ${env.sdk}');
  }
  if (env.flutter != null) {
    print('🐦 Detected Flutter constraint: ${env.flutter}');
  }

  // Generate CLAUDE.md aggregator with expanded absolute paths
  final genericFiles = Directory(genericKnowledgeDir)
      .listSync()
      .whereType<File>()
      .map((f) => p.basename(f.path))
      .where((name) => name.endsWith('.md'))
      .toList()
      ..sort();

  writeFile(claudeMdPath, claudeMdTemplate(
    workspacePath: claudeDir,
    projectName: projectName,
    genericFiles: genericFiles,
    sdkConstraint: env.sdk,
    flutterConstraint: env.flutter,
  ));

  // Create symlinks
  Link(claudeLinkPath).createSync(p.join(claudeDir, '.claude'));
  Link(claudeMdLinkPath).createSync(claudeMdPath);

  print('\n✓ CLAUDE.md → $claudeMdPath');
  print('✓ .claude/  → ${p.join(claudeDir, '.claude')}');
  print('\nWorkspace: $claudeDir');
  print('Project  : $projectName');

  // Sensitivity configuration
  print('\n───────────────────────────────────────');
  print('Sensitivity & diagnostics configuration');
  print('───────────────────────────────────────');
  final enableSensitivity = confirm('Enable sensitivity protection?');

  String scanScope = 'lib';
  String scanTrigger = 'on_setup';
  bool diagnosticReporting = false;

  if (enableSensitivity) {
    print('\nScan scope:');
    print('  1. lib/ only (recommended)');
    print('  2. Full project');
    print('  3. Scoped to handoff files only');
    stdout.write('> ');
    final scopeInput = stdin.readLineSync()?.trim() ?? '1';
    switch (scopeInput) {
      case '2':
        scanScope = 'full';
      case '3':
        scanScope = 'handoff';
      default:
        scanScope = 'lib';
    }

    print('\nScan trigger:');
    print('  1. On setup (when files changed) (recommended)');
    print('  2. On demand only (claudart scan)');
    stdout.write('> ');
    final triggerInput = stdin.readLineSync()?.trim() ?? '1';
    scanTrigger = triggerInput == '2' ? 'on_demand' : 'on_setup';

    diagnosticReporting =
        confirm('Share anonymous diagnostic logs?');
  }

  // Write config.json to workspace
  final config = WorkspaceConfig(
    sensitivityMode: enableSensitivity,
    scanScope: scanScope,
    scanTrigger: scanTrigger,
    diagnosticReporting: diagnosticReporting,
    projectRoot: cwd,
  );
  saveConfig(config);

  if (enableSensitivity) {
    print('\n✓ Sensitivity protection enabled (scope: $scanScope, '
        'trigger: $scanTrigger)');
  }

  print('\nNext: run `claudart setup` to begin a session.\n');
}

void _checkExisting(String path, String label) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    print('\n⚠  Removing existing symlink: $label');
    Link(path).deleteSync();
  } else if (type != FileSystemEntityType.notFound) {
    print('\n✗ $label already exists as a real file or directory.');
    print('  Move or delete it before running claudart link.\n');
    exit(1);
  }
}

String _detectProjectName() {
  // Try git remote name
  try {
    final result = Process.runSync('git', ['remote', 'get-url', 'origin']);
    final url = (result.stdout as String).trim();
    if (url.isNotEmpty) {
      final name = url.split('/').last.replaceAll('.git', '').trim();
      if (name.isNotEmpty) return name;
    }
  } catch (_) {}

  // Fall back to directory name
  return p.basename(Directory.current.path);
}

