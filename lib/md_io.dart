import 'dart:io';
import 'package:path/path.dart' as p;
import 'pipeline/pipeline_context.dart' show ScopeFile;
import 'ui/line_editor.dart' as editor;

/// Reads a section from a markdown file between `## Header` and the next `## `.
/// Returns the trimmed content, or `_Not yet determined._` if not found.
String readSection(String content, String header) {
  final pattern = RegExp(
    r'## ' + RegExp.escape(header) + r'\n+([\s\S]*?)(?=\n## |\s*$)',
  );
  final match = pattern.firstMatch(content);
  final raw = match?.group(1) ?? '_Not yet determined._';
  return raw.replaceAll(RegExp(r'\n*-{3,}\n*$'), '').trim();
}

/// Replaces the content of a section in markdown, preserving surrounding sections.
String updateSection(String content, String header, String newContent) {
  final pattern = RegExp(
    r'(## ' + RegExp.escape(header) + r'\n+)([\s\S]*?)(?=\n## |\s*$)',
  );
  if (pattern.hasMatch(content)) {
    return content.replaceFirstMapped(pattern, (m) => '${m.group(1)}$newContent\n');
  }
  // Section not found — append it
  return '$content\n## $header\n\n$newContent\n';
}

/// Reads the Status line value from the handoff.
String readStatus(String content) {
  final match = RegExp(r'## Status\n+(\S[^\n]*)').firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

/// Updates the Status line in the handoff.
String updateStatus(String content, String status) {
  return content.replaceFirstMapped(
    RegExp(r'(## Status\n+)(\S[^\n]*)'),
    (m) => '${m.group(1)}$status',
  );
}

String readFile(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// Parses `### Files in play` bullet lines from a scope section.
/// Line format: `- \`relative/path\` — description`
/// Returns a list of [ScopeFile] with absolute paths resolved via [projectRoot].
List<ScopeFile> parseScopeFiles(String scopeSection, String projectRoot) {
  final result  = <ScopeFile>[];
  var   inFiles = false;
  for (final line in scopeSection.split('\n')) {
    if (line.startsWith('### Files in play')) { inFiles = true; continue; }
    if (inFiles && line.startsWith('###')) break;
    if (!inFiles) continue;
    final match = RegExp(r'^-\s+`([^`]+)`').firstMatch(line.trim());
    if (match != null) {
      final rel = match.group(1)!;
      result.add((relative: rel, absolute: p.join(projectRoot, rel)));
    }
  }
  return result;
}

void writeFile(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Prompts the user with a question and returns trimmed input.
/// If [optional] is true, empty input returns null.
String? prompt(String question, {bool optional = false}) {
  while (true) {
    stdout.write('\n$question');
    if (optional) stdout.write(' (press enter to skip)');
    stdout.write('\n');
    final input = editor.readLine(optional: optional);
    if (input == null && !optional) return null;  // EOF/non-TTY — can't prompt
    if (optional) return input?.isEmpty == true ? null : input;
    if (input != null && input.isNotEmpty) return input;
    // Non-optional and empty — re-prompt once with hint, don't recurse.
    stdout.write('  (required — please enter a value)\n');
  }
}

/// Prompts yes/no. Returns true for yes.
bool confirm(String question) {
  stdout.write('\n$question [y/n]\n');
  final input = editor.readLine(optional: true);
  return input?.toLowerCase() == 'y' || input?.toLowerCase() == 'yes';
}
