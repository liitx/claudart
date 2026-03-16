import 'dart:io';
import 'package:path/path.dart' as p;
import '../md_io.dart';
import '../paths.dart';
import '../handoff_template.dart';

Future<void> runTeardown() async {
  print('\n═══════════════════════════════════════');
  print('  IVI SESSION TEARDOWN');
  print('═══════════════════════════════════════');

  final handoff = readFile(handoffPath);
  if (handoff.isEmpty) {
    print('\nNo active handoff found. Nothing to tear down.\n');
    exit(0);
  }

  if (!confirm('Is the bug confirmed resolved?')) {
    print('\nCome back when the fix is confirmed. Continue with /debug or /suggest.\n');
    exit(0);
  }

  final fixSummary = prompt('Briefly describe the fix (one or two sentences)');

  // Extract session info
  final bug = readSection(handoff, 'Bug');
  final rootCause = readSection(handoff, 'Root Cause');
  final scopeSection = _extractSection(handoff, 'Scope');
  final filesInPlay = _readSubSection(scopeSection, 'Files in play');
  final mustNotTouch = _readSubSection(scopeSection, 'Must not touch');
  final debugProgress = _extractSection(handoff, 'Debug Progress');
  final filesChanged = _readSubSection(debugProgress, 'What changed (files modified)');
  final branch = _extractBranch(handoff);

  print('\n───────────────────────────────────────');
  print('Extracting learnings from session...');
  print('───────────────────────────────────────');

  // Prompt for what was genuinely useful
  print('\nHelp categorize this session for skills.md:\n');

  final category = prompt(
    'Root cause category?\n  (e.g. bloc-event-handling / provider-state / api-mapping / widget-lifecycle / ffi-bridge)',
  );

  final hotFiles = prompt(
    'Which files were confirmed key to the fix? (comma-separated, or "none")',
    optional: true,
  );

  final coldFiles = prompt(
    'Any files explored but NOT the root cause? (comma-separated, or skip)',
    optional: true,
  );

  final pattern = prompt(
    'Describe the root cause pattern generically (one sentence)\n  e.g. "BLoC emits stale state when event fires before previous async resolves"',
  );

  final fixPattern = prompt(
    'Describe the fix pattern generically (one sentence)\n  e.g. "Added restartable transformer to ensure sequential event processing"',
  );

  // Update skills.md
  _updateSkills(
    branch: branch,
    category: category!,
    hotFiles: hotFiles,
    coldFiles: coldFiles,
    pattern: pattern!,
    fixPattern: fixPattern!,
  );

  // Archive handoff
  _archiveHandoff(handoff, branch);

  // Reset handoff
  writeFile(handoffPath, blankHandoff);

  // Suggest commit message
  final area = _areaFromCategory(category);
  final commitMsg = _buildCommitMessage(area, bug, rootCause, fixSummary!);

  print('\n✓ Skills updated: $skillsPath');
  print('✓ Handoff archived: ${p.join(archiveDir, _archiveName(branch))}');
  print('✓ Handoff reset.\n');
  print('───────────────────────────────────────');
  print('Suggested commit message:\n');
  print(commitMsg);
  print('───────────────────────────────────────');
  print('\nRemember: do not push to remote. Open a merge request from your branch.\n');
}

void _updateSkills({
  required String branch,
  required String category,
  String? hotFiles,
  String? coldFiles,
  required String pattern,
  required String fixPattern,
}) {
  var skills = readFile(skillsPath);
  if (skills.isEmpty) {
    skills = _defaultSkillsTemplate();
  }

  final date = DateTime.now().toIso8601String().split('T').first;

  // Append to Root Cause Patterns
  final newPattern = '- **$category**: $pattern → Fix: $fixPattern';
  skills = _appendToSection(skills, 'Root Cause Patterns', newPattern);

  // Update Hot Paths
  if (hotFiles != null && hotFiles.toLowerCase() != 'none') {
    final files = hotFiles.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty);
    for (final file in files) {
      skills = _incrementHotPath(skills, category, file);
    }
  }

  // Update Anti-patterns
  if (coldFiles != null && coldFiles.toLowerCase() != 'none') {
    final files = coldFiles.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty);
    for (final file in files) {
      final entry = '- `$file` — explored for $category, not the root cause';
      skills = _appendToSection(skills, 'Anti-patterns', entry);
    }
  }

  // Branch notes
  if (branch != 'unknown') {
    final note = '- `$branch` ($date): $category resolved';
    skills = _appendToSection(skills, 'Branch Notes', note);
  }

  // Session index
  final indexEntry = '`$branch` | $date | $category | resolved';
  skills = _appendToSection(skills, 'Session Index', indexEntry);

  writeFile(skillsPath, skills);
}

void _archiveHandoff(String content, String branch) {
  Directory(archiveDir).createSync(recursive: true);
  final name = _archiveName(branch);
  writeFile(p.join(archiveDir, name), content);
}

String _archiveName(String branch) {
  final date = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final safeBranch = branch.replaceAll('/', '_').replaceAll(' ', '_');
  return 'handoff_${safeBranch}_$date.md';
}

String _extractBranch(String content) {
  final match = RegExp(r'Branch: ([^\n|]+)').firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

String _extractSection(String content, String header) {
  final match = RegExp(
    r'## ' + RegExp.escape(header) + r'\n+([\s\S]*?)(?=\n## |\s*$)',
  ).firstMatch(content);
  return match?.group(1)?.trim() ?? '';
}

String _readSubSection(String section, String subheader) {
  final match = RegExp(
    r'### ' + RegExp.escape(subheader) + r'\n+([\s\S]*?)(?=\n### |\s*$)',
  ).firstMatch(section);
  return match?.group(1)?.trim() ?? '_Nothing yet._';
}

String _appendToSection(String content, String header, String newEntry) {
  final pattern = RegExp(
    r'(## ' + RegExp.escape(header) + r'\n+)([\s\S]*?)(?=\n## |\s*$)',
  );
  final match = pattern.firstMatch(content);
  if (match == null) return '$content\n## $header\n\n$newEntry\n';

  final existing = match.group(2)!.trim();
  final isBlank = existing.startsWith('_No') || existing.startsWith('_None');
  final updated = isBlank ? newEntry : '$existing\n$newEntry';
  return content.replaceFirst(pattern, '${match.group(1)}$updated\n');
}

String _incrementHotPath(String skills, String area, String file) {
  // Try to find and increment existing ↑ entry
  final existingPattern = RegExp(r'- `' + RegExp.escape(file) + r'` (↑+)');
  if (existingPattern.hasMatch(skills)) {
    return skills.replaceFirstMapped(existingPattern, (m) {
      return '- `$file` ${m.group(1)}↑';
    });
  }
  // Not found — add under Hot Paths with the area as context
  final entry = '- `$file` ↑  [$area]';
  return _appendToSection(skills, 'Hot Paths — media_ivi', entry);
}

String _areaFromCategory(String category) {
  if (category.contains('bloc') || category.contains('event')) return 'bloc';
  if (category.contains('provider') || category.contains('riverpod')) return 'provider';
  if (category.contains('api') || category.contains('repository')) return 'api';
  if (category.contains('widget') || category.contains('ui')) return 'ui';
  if (category.contains('ffi') || category.contains('bridge')) return 'ffi';
  return 'media_ivi';
}

String _buildCommitMessage(String area, String bug, String rootCause, String fix) {
  final bugLine = bug.replaceAll('\n', ' ').trim();
  final rootLine = rootCause == '_Not yet determined._'
      ? ''
      : ' Root cause: ${rootCause.replaceAll('\n', ' ').trim()}.';
  final fixLine = fix.trim();

  return 'fix($area): ${_firstSentence(bugLine)}\n\n$fixLine.$rootLine';
}

String _firstSentence(String s) {
  final dot = s.indexOf('.');
  if (dot > 0 && dot < 80) return s.substring(0, dot);
  return s.length > 72 ? '${s.substring(0, 72)}…' : s;
}

String _defaultSkillsTemplate() => '''# dc-flutter / media_ivi — Accumulated Skills

> Updated by `claudart teardown` after each resolved session.
> Read by `/suggest` and `/debug` at the start of every session.

---

## Hot Paths — media_ivi

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
