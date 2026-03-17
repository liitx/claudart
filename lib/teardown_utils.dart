/// Pure logic extracted from teardown.dart for testability.

String extractBranch(String content) {
  final match = RegExp(r'Branch: ([^\n|]+)').firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

String extractSection(String content, String header) {
  final match = RegExp(
    r'## ' + RegExp.escape(header) + r'\n+([\s\S]*?)(?=\n## |\s*$)',
  ).firstMatch(content);
  return match?.group(1)?.trim() ?? '';
}

String readSubSection(String section, String subheader) {
  final match = RegExp(
    r'### ' + RegExp.escape(subheader) + r'\n+([\s\S]*?)(?=\n### |\s*$)',
  ).firstMatch(section);
  return match?.group(1)?.trim() ?? '_Nothing yet._';
}

String appendToSection(String content, String header, String newEntry) {
  final pattern = RegExp(
    r'(## ' + RegExp.escape(header) + r'\n+)([\s\S]*?)(?=\n## |\s*$)',
  );
  final match = pattern.firstMatch(content);
  if (match == null) return '$content\n## $header\n\n$newEntry\n';

  final existing = match.group(2)!.trim();

  // Separate blockquote metadata lines (e.g. "> Description of section") from
  // actual content. Metadata lines must not be mistaken for real entries, and
  // must not prevent blank detection when they precede a placeholder.
  final lines = existing.split('\n');
  final metaLines = lines.where((l) => l.trimLeft().startsWith('>')).toList();
  final contentOnly = lines
      .where((l) => !l.trimLeft().startsWith('>'))
      .join('\n')
      .trim();

  final isBlank = contentOnly.isEmpty ||
      contentOnly.startsWith('_No') ||
      contentOnly.startsWith('_None');

  final meta = metaLines.isNotEmpty ? '${metaLines.join('\n')}\n\n' : '';
  final updated = isBlank ? '$meta$newEntry' : '$existing\n$newEntry';
  return content.replaceFirst(pattern, '${match.group(1)}$updated\n');
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

String areaFromCategory(String category) {
  if (category.contains('api')) return 'api';
  if (category.contains('concurrency') || category.contains('async')) return 'async';
  if (category.contains('config')) return 'config';
  if (category.contains('filesystem') || category == 'io-filesystem') return 'io';
  if (category.contains('state')) return 'state';
  if (category.contains('data') || category.contains('pars')) return 'data';
  return 'fix';
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
