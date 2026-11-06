import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import '../session/md_io.dart';
import '../config/paths.dart';
import '../project/knowledge_templates.dart';
import '../templates/handoff_template.dart';
import '../templates/suggest_template.dart';
import '../templates/debug_template.dart';
import '../templates/save_template.dart';
import '../templates/teardown_template.dart';
import '../ui/render.dart' as render;
import '../io/process_runner.dart';
import '../generated/user_text.g.dart';
import '../io/process_exit.dart';

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
  print(render.header('CLAUDART WORKSPACE INIT'));
  print(UserText.initWorkspace.format({'claudeDir': claudeDir}));

  // Check if already initialized
  if (Directory(genericKnowledgeDir).existsSync()) {
    print(UserText.initWorkspaceAlreadyInitialized.template);
    if (!confirm('Re-initialize and overwrite starter files?')) {
      print(UserText.initAbortedRunClaudartInitProjectName.template);
      exitProcess(0);
    }
  }

  // Detect Dart version for version-tagged starters
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
  _writeIfAbsent(p.join(genericKnowledgeDir, 'dart.md'), dartTemplate(dartVersion));
  _writeIfAbsent(p.join(genericKnowledgeDir, 'testing.md'), testingTemplate);

  // Write Claude Code slash commands into workspace.
  // 'workspace' is the project label for global default commands — re-running
  // `claudart link` in a real project overrides these with the project name.
  const globalLabel = 'workspace';
  writeFile(p.join(claudeCommandsDir, 'suggest-$globalLabel.md'), suggestCommandTemplate(claudeDir, globalLabel));
  writeFile(p.join(claudeCommandsDir, 'debug-$globalLabel.md'), debugCommandTemplate(claudeDir, globalLabel));
  writeFile(p.join(claudeCommandsDir, 'save-$globalLabel.md'), saveCommandTemplate(claudeDir, globalLabel));
  writeFile(p.join(claudeCommandsDir, 'teardown-$globalLabel.md'), teardownCommandTemplate(claudeDir, globalLabel));

  // Write blank handoff and skills if not present
  _writeIfAbsent(handoffPath, blankHandoff);
  _writeIfAbsent(skillsPath, _blankSkills);

  print(UserText.initGenericKnowledgeFilesWrittenTo.format({'genericKnowledgeDir': genericKnowledgeDir}));
  print(UserText.initSlashCommandsWrittenTo.format({'claudeCommandsDir': claudeCommandsDir}));
  print(UserText.initNextRegisterYourProjectWith.template);
  print(UserText.initClaudartInitProjectYourProjectName.template);
}

Future<void> _initProject(String name) async {
  print(render.header('CLAUDART PROJECT INIT: $name'));

  if (!Directory(genericKnowledgeDir).existsSync()) {
    print(UserText.initWorkspaceNotInitializedRunClaudartInit.template);
    exitProcess(1);
  }

  final projectFile = p.join(projectsKnowledgeDir, '$name.md');

  if (File(projectFile).existsSync()) {
    print(UserText.initProjectKnowledgeFileAlreadyExists.format({'projectFile': projectFile}));
    if (!confirm('Overwrite with a fresh template?')) {
      print(UserText.initKeptExistingFile.template);
      exitProcess(0);
    }
  }

  writeFile(projectFile, projectTemplate(name));

  print(UserText.initProjectKnowledgeFileCreated.format({'projectFile': projectFile}));
  print(UserText.initNextFromYourProjectRootRun.template);
  print(UserText.initClaudartLink.format({'name': name}));
}

void _writeIfAbsent(String path, String content) {
  if (!File(path).existsSync()) {
    writeFile(path, content);
  }
}

Future<String?> _detectVersion(String cmd, List<String> args) async {
  try {
    final result = await const RealProcessRunner().run(cmd, args);
    final out = (result.stdout as String) + (result.stderr as String);
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(out);
    return match?.group(1);
  } on ProcessException catch (_) {
    return null;
  }
}

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
