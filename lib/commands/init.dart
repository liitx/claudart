import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import '../md_io.dart';
import '../paths.dart';
import '../knowledge_templates.dart';
import '../commands/suggest_template.dart';
import '../commands/debug_template.dart';
import '../commands/teardown_template.dart';

Future<void> runInit(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Add a project knowledge file to the workspace');

  final parsed = parser.parse(args);
  final projectName = parsed['project'] as String?;

  if (projectName != null) {
    await _initProject(projectName);
  } else {
    await _initWorkspace();
  }
}

Future<void> _initWorkspace() async {
  print('\n═══════════════════════════════════════');
  print('  CLAUDART WORKSPACE INIT');
  print('═══════════════════════════════════════');
  print('\nWorkspace: $claudeDir');

  // Check if already initialized
  if (Directory(genericKnowledgeDir).existsSync()) {
    print('\n⚠  Workspace already initialized.');
    if (!confirm('Re-initialize and overwrite starter files?')) {
      print('\nAborted. Run `claudart init --project <name>` to add a project.\n');
      exit(0);
    }
  }

  // Detect Flutter/Dart versions for version-tagged starters
  final flutterVersion = await _detectVersion('flutter', ['--version', '--machine']) ?? '3.x';
  final dartVersion = await _detectVersion('dart', ['--version']) ?? '3.x';

  // Create directory structure
  for (final dir in [
    genericKnowledgeDir,
    projectsKnowledgeDir,
    archiveDir,
    claudeCommandsDir,
  ]) {
    Directory(dir).createSync(recursive: true);
  }

  // Write generic knowledge starters
  _writeIfAbsent(p.join(genericKnowledgeDir, 'dart_flutter.md'),
      dartFlutterTemplate(flutterVersion, dartVersion));
  _writeIfAbsent(p.join(genericKnowledgeDir, 'bloc.md'), blocTemplate);
  _writeIfAbsent(p.join(genericKnowledgeDir, 'riverpod.md'), riverpodTemplate);
  _writeIfAbsent(p.join(genericKnowledgeDir, 'testing.md'), testingTemplate);

  // Write Claude Code slash commands into workspace
  writeFile(p.join(claudeCommandsDir, 'suggest.md'), suggestCommandTemplate(claudeDir));
  writeFile(p.join(claudeCommandsDir, 'debug.md'), debugCommandTemplate(claudeDir));
  writeFile(p.join(claudeCommandsDir, 'teardown.md'), teardownCommandTemplate(claudeDir));

  // Write blank handoff and skills if not present
  _writeIfAbsent(handoffPath, _blankHandoff);
  _writeIfAbsent(skillsPath, _blankSkills);

  print('\n✓ Generic knowledge files written to $genericKnowledgeDir');
  print('✓ Slash commands written to $claudeCommandsDir');
  print('\nNext: register your project with:');
  print('  claudart init --project <your-project-name>\n');
}

Future<void> _initProject(String name) async {
  print('\n═══════════════════════════════════════');
  print('  CLAUDART PROJECT INIT: $name');
  print('═══════════════════════════════════════');

  if (!Directory(genericKnowledgeDir).existsSync()) {
    print('\n✗ Workspace not initialized. Run `claudart init` first.\n');
    exit(1);
  }

  final projectFile = p.join(projectsKnowledgeDir, '$name.md');

  if (File(projectFile).existsSync()) {
    print('\n⚠  Project knowledge file already exists: $projectFile');
    if (!confirm('Overwrite with a fresh template?')) {
      print('\nKept existing file.\n');
      exit(0);
    }
  }

  writeFile(projectFile, projectTemplate(name));

  print('\n✓ Project knowledge file created: $projectFile');
  print('\nNext: from your project root, run:');
  print('  claudart link $name\n');
}

void _writeIfAbsent(String path, String content) {
  if (!File(path).existsSync()) {
    writeFile(path, content);
  }
}

Future<String?> _detectVersion(String cmd, List<String> args) async {
  try {
    final result = await Process.run(cmd, args);
    final out = (result.stdout as String) + (result.stderr as String);
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(out);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}

const String _blankHandoff = '''# Agent Handoff

> Source of truth between suggest and debug agents.
> Run `claudart setup` to begin a new session.

---

## Status

suggest-investigating

---

## Bug

_Not yet determined._

---

## Expected Behavior

_Not yet determined._

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### Classes / methods in play
_Not yet determined._

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

const String _blankSkills = '''# Accumulated Skills
> Updated by claudart teardown after each resolved session.

---

## Hot Paths

_No sessions recorded yet._

---

## Root Cause Patterns

_No patterns recorded yet._

---

## Anti-patterns

_None recorded yet._

---

## Branch Notes

_None recorded yet._

---

## Session Index

_No sessions recorded yet._
''';
