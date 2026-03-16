import 'dart:io';
import 'package:path/path.dart' as p;
import '../md_io.dart';
import '../paths.dart';
import '../knowledge_templates.dart';

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
  final env = _readProjectEnv(cwd);
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

({String? sdk, String? flutter}) _readProjectEnv(String projectDir) {
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return (sdk: null, flutter: null);

  final content = pubspec.readAsStringSync();

  // Extract environment block, then pull sdk/flutter lines from it
  final envBlock = RegExp(
    r'^environment\s*:\s*\n((?:[ \t]+\S[^\n]*\n?)+)',
    multiLine: true,
  ).firstMatch(content)?.group(1) ?? '';

  String? extract(String key) {
    final m = RegExp(
      r'''^\s*''' + key + r'''\s*:\s*['"]?([^'"\n]+?)['"]?\s*$''',
      multiLine: true,
    ).firstMatch(envBlock);
    return m?.group(1)?.trim();
  }

  return (sdk: extract('sdk'), flutter: extract('flutter'));
}
