// Pure logic extracted from teardown.dart for testability.

String extractBranch(String content) {
  final match = RegExp(r'Branch: ([^\n|]+)').firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

String extractSection(String content, String header) {
  final match = RegExp(
    r'## ' + RegExp.escape(header) + r'(?:\r?\n)+([\s\S]*?)(?=\r?\n## |\s*$)',
  ).firstMatch(content);
  return match?.group(1)?.trim() ?? '';
}

String readSubSection(String section, String subheader) {
  final match = RegExp(
    r'### ' + RegExp.escape(subheader) + r'(?:\r?\n)+([\s\S]*?)(?=\r?\n### |\s*$)',
  ).firstMatch(section);
  return match?.group(1)?.trim() ?? '_Nothing yet._';
}

String appendToSection(String content, String header, String newEntry) {
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  final replacement = newEntry.replaceAll('\r\n', '\n').replaceAll('\n', newline);
  final pattern = RegExp(
    r'(## ' + RegExp.escape(header) + r'(?:\r?\n)+)([\s\S]*?)(?=\r?\n## |\s*$)',
  );
  final match = pattern.firstMatch(content);
  if (match == null) return '$content$newline## $header$newline$newline$replacement$newline';

  final existing = match.group(2)!.trim();

  // Separate blockquote metadata lines (e.g. "> Description of section") from
  // actual content. Metadata lines must not be mistaken for real entries, and
  // must not prevent blank detection when they precede a placeholder.
  final lines = existing.split(RegExp(r'\r?\n'));
  final metaLines = lines.where((l) => l.trimLeft().startsWith('>')).toList();
  final contentOnly = lines
      .where((l) => !l.trimLeft().startsWith('>'))
      .join('\n')
      .trim();

  final isBlank = contentOnly.isEmpty ||
      contentOnly.startsWith('_No') ||
      contentOnly.startsWith('_None');

  final meta = metaLines.isNotEmpty ? '${metaLines.join(newline)}$newline$newline' : '';
  final updated = isBlank ? '$meta$replacement' : '$existing$newline$replacement';
  return content.replaceFirst(pattern, '${match.group(1)}$updated$newline');
}

String incrementHotPath(String skills, String area, String file) {
  final existingPattern = RegExp(r'- `' + RegExp.escape(file) + r'` (↑+)');
  if (existingPattern.hasMatch(skills)) {
    return skills.replaceFirstMapped(existingPattern, (m) {
      return '- `$file` ${m.group(1)}↑';
    });
  }
  final entry = '- `$file` ↑  [$area]';
  return appendToSection(skills, 'Hot Paths', entry);
}


String buildCommitMessage(String area, String bug, String rootCause, String fix) {
  final bugLine = bug.replaceAll('\n', ' ').trim();
  final rootLine = rootCause == '_Not yet determined._'
      ? ''
      : ' Root cause: ${rootCause.replaceAll('\n', ' ').trim()}.';
  final fixLine = fix.trim();
  return 'fix($area): ${firstSentence(bugLine)}\n\n$fixLine.$rootLine';
}

String firstSentence(String s) {
  final dot = s.indexOf('.');
  if (dot > 0 && dot < 80) return s.substring(0, dot);
  return s.length > 72 ? '${s.substring(0, 72)}…' : s;
}

String archiveName(String branch) {
  final date = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final safeBranch = branch.replaceAll('/', '_').replaceAll(' ', '_');
  return 'handoff_${safeBranch}_$date.md';
}

/// Returns the text of each unchecked `- [ ] …` item in the
/// `## Pending Issues` section. Checked items (`- [x]`) are skipped.
/// Returns empty list when the section is absent or has no unchecked items.
List<String> extractPendingIssues(String handoff) {
  final section = extractSection(handoff, 'Pending Issues');
  if (section.isEmpty) return [];
  return section
      .split('\n')
      .where((l) => l.trimLeft().startsWith('- [ ]'))
      .map((l) => l.replaceFirst(RegExp(r'^\s*- \[ \]\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Builds the body of a `## Pending Issues` section from a list of
/// descriptions. Each item becomes an unchecked `- [ ] …` line.
/// Returns the placeholder string when [issues] is empty.
String buildPendingIssuesSection(List<String> issues) {
  if (issues.isEmpty) return '_None recorded yet._';
  return issues.map((i) => '- [ ] $i').join('\n');
}
