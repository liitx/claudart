import 'dart:io';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../logging/logger.dart';
import '../md_io.dart';
import '../paths.dart';
import '../handoff_template.dart';
import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';
import '../sensitivity/token_map.dart';
import 'scan.dart';

Future<void> runSetup({String projectPath = '.'}) async {
  print('\n═══════════════════════════════════════');
  print('  CLAUDART SESSION SETUP');
  print('═══════════════════════════════════════');

  // Resolve project path
  final resolvedPath = p.isAbsolute(projectPath)
      ? projectPath
      : p.normalize(p.join(Directory.current.path, projectPath));

  if (!Directory(resolvedPath).existsSync()) {
    print('\n✗ Path not found: $resolvedPath');
    exit(1);
  }

  // Check for active handoff
  final existing = readFile(handoffPath);
  if (existing.isNotEmpty) {
    final status = readStatus(existing);
    if (status != 'suggest-investigating' && !existing.contains('_Not yet determined._\n\n---\n\n## Expected')) {
      print('\n⚠  Active handoff found (status: $status)');
      if (!confirm('Overwrite and start a new session?')) {
        print('\nSetup cancelled. Run /suggest or /debug to continue the existing session.');
        exit(0);
      }
    }
  }

  // Detect git branch from project path
  final branch = await _detectBranch(resolvedPath);

  // Read skills for relevant context
  final skills = readFile(skillsPath);
  if (skills.isNotEmpty && !skills.contains('_No sessions recorded yet._')) {
    print('\n📚 Skills loaded — relevant patterns will inform /suggest.');
  }

  // Prompt for session context
  print('\nAnswer the following. Be specific — this seeds the handoff for /suggest.\n');

  final bug = prompt('1. What is the bug? (actual behavior)');
  final expected = prompt('2. What should be happening? (expected behavior)');
  final files = prompt(
    '3. Any files already in mind?',
    optional: true,
  );
  final blocs = prompt(
    '4. Any BLoC events, provider names, or API calls involved?',
    optional: true,
  );

  // Confirm before writing
  print('\n───────────────────────────────────────');
  print('Project : $resolvedPath');
  print('Branch  : $branch');
  print('Bug     : $bug');
  print('Expected: $expected');
  if (files != null) print('Files   : $files');
  if (blocs != null) print('BLoCs   : $blocs');
  print('───────────────────────────────────────');

  if (!confirm('Write handoff with this context?')) {
    print('\nSetup cancelled.');
    exit(0);
  }

  // Load config for sensitivity + scan
  final config = loadConfig();

  // Run scan if sensitivity mode is on and trigger is 'on_setup'
  if (config.sensitivityMode && config.scanTrigger == 'on_setup') {
    await runScan(scope: config.scanScope);
  }

  // Build handoff content
  final date = DateTime.now().toIso8601String().split('T').first;
  final projectName = _detectProjectName(resolvedPath);
  var content = handoffTemplate(
    branch: branch,
    date: date,
    bug: bug!,
    expected: expected!,
    projectName: projectName,
    files: files,
    blocs: blocs,
  );

  // Abstract sensitive tokens from handoff if sensitivity mode on
  if (config.sensitivityMode) {
    final tokenMapPath = p.join(claudeDir, 'token_map.json');
    final tokenMap = TokenMap.load(tokenMapPath);
    content = abstractor.abstract(content, tokenMap, defaultDetector);
    if (!abstractor.isNotSensitive(content, defaultDetector)) {
      print('\n⚠  Handoff still contains sensitive tokens after abstraction.');
      print('   Review handoff.md manually before sharing.');
    }
  }

  writeFile(handoffPath, content);

  // Log the setup interaction
  final logger = SessionLogger(sensitivityMode: config.sensitivityMode);
  logger.logInteraction(
    command: 'setup',
    outcome: 'ok',
    platform: Platform.operatingSystem,
  );

  print('\n✓ Handoff written to $handoffPath');
  print('\nNext step:');
  print('  Open your editor and run /suggest to begin exploration.');
  print('  Or run /debug if you already know the root cause.\n');
}

String _detectProjectName(String projectPath) {
  try {
    final result = Process.runSync('git', ['remote', 'get-url', 'origin'], workingDirectory: projectPath);
    final url = (result.stdout as String).trim();
    if (url.isNotEmpty) {
      final name = url.split('/').last.replaceAll('.git', '').trim();
      if (name.isNotEmpty) return name;
    }
  } catch (_) {}
  return p.basename(projectPath);
}

Future<String> _detectBranch(String projectPath) async {
  try {
    final result = await Process.run(
      'git',
      ['branch', '--show-current'],
      workingDirectory: projectPath,
    );
    final branch = (result.stdout as String).trim();
    if (branch.isNotEmpty) {
      print('\n🌿 Branch detected: $branch');
      return branch;
    }
  } catch (_) {}

  return prompt('Could not detect git branch. Enter branch name manually') ?? 'unknown';
}
