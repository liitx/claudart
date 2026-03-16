import 'dart:io';
import 'package:path/path.dart' as p;
import '../md_io.dart';
import '../paths.dart';
import 'init.dart';
import 'link.dart';
import 'setup.dart';

/// Interactive launcher — runs when `claudart` is invoked with no arguments.
/// Lists workspace projects and guides the user into the debug/suggest workflow.
Future<void> runLauncher() async {
  print('\n═══════════════════════════════════════');
  print('  CLAUDART');
  print('═══════════════════════════════════════');

  // Check workspace is initialized
  if (!Directory(genericKnowledgeDir).existsSync()) {
    print('\nWorkspace not initialized.');
    if (confirm('Initialize workspace now?')) {
      await runInit([]);
    } else {
      print('\nRun `claudart init` to set up the workspace.\n');
      exit(0);
    }
  }

  // List available projects
  final projectsDir = Directory(projectsKnowledgeDir);
  List<String> projects;
  if (projectsDir.existsSync()) {
    projects = projectsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList()
      ..sort();
  } else {
    projects = [];
  }

  print('\nWorkspace: $claudeDir');

  if (projects.isEmpty) {
    print('\nNo projects found in workspace.');
    print('Run `claudart init --project <name>` to add a project.\n');
    exit(0);
  }

  print('\nAvailable projects:');
  for (var i = 0; i < projects.length; i++) {
    final linked = _isLinked(projects[i]);
    print('  ${i + 1}. ${projects[i]}${linked ? '  (linked)' : ''}');
  }

  // Pick a project
  final projectName = _pickProject(projects);

  // New or existing bug?
  print('\nWorkflow:');
  print('  1. New bug — start a fresh session');
  print('  2. Existing bug — resume active handoff');

  final choice = _pickNumber('Choose', 2);

  if (choice == 1) {
    // New bug: ensure link exists, then setup
    await _ensureLinked(projectName);
    await runSetup(projectPath: Directory.current.path);
  } else {
    // Existing bug: check handoff status
    final handoff = readFile(handoffPath);
    if (handoff.isEmpty) {
      print('\nNo active handoff found. Starting a new session instead.');
      await _ensureLinked(projectName);
      await runSetup(projectPath: Directory.current.path);
    } else {
      final status = readStatus(handoff);
      print('\nActive handoff status: $status');
      print('\nNext steps:');
      _printNextSteps(status);
    }
  }
}

String _pickProject(List<String> projects) {
  if (projects.length == 1) {
    print('\nUsing project: ${projects.first}');
    return projects.first;
  }
  while (true) {
    stdout.write('\nSelect project (1–${projects.length}) > ');
    final input = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(input);
    if (n != null && n >= 1 && n <= projects.length) {
      return projects[n - 1];
    }
    print('Please enter a number between 1 and ${projects.length}.');
  }
}

int _pickNumber(String prompt, int max) {
  while (true) {
    stdout.write('\n$prompt (1–$max) > ');
    final input = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(input);
    if (n != null && n >= 1 && n <= max) return n;
    print('Please enter a number between 1 and $max.');
  }
}

bool _isLinked(String projectName) {
  // A project is "linked" if the workspace CLAUDE.md references it.
  // We check the generated CLAUDE.md for the project name.
  final claudeMd = readFile(claudeMdPath);
  return claudeMd.contains('Project: $projectName');
}

Future<void> _ensureLinked(String projectName) async {
  // Check if cwd already has a symlink to the workspace
  final claudeLink = p.join(Directory.current.path, '.claude');
  final type = FileSystemEntity.typeSync(claudeLink, followLinks: false);
  if (type == FileSystemEntityType.link) return; // already linked

  print('\nProject not linked to current directory.');
  if (confirm('Link workspace into current directory now?')) {
    await runLink([projectName]);
  }
}

void _printNextSteps(String status) {
  switch (status) {
    case 'suggest-investigating':
      print('  → Open your editor and run /suggest to continue exploration.');
    case 'ready-for-debug':
      print('  → Root cause identified. Run /debug to implement the fix.');
    case 'debug-in-progress':
      print('  → Fix in progress. Run /debug to continue.');
    case 'needs-suggest':
      print('  → Debug hit a blocker. Run /suggest for broader exploration.');
    default:
      print('  → Run /suggest to begin or /debug if root cause is known.');
  }
  print('');
}
