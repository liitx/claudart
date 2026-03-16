import '../md_io.dart';
import '../paths.dart';

void runStatus() {
  final content = readFile(handoffPath);
  if (content.isEmpty) {
    print('\nNo active handoff. Run: claudart setup\n');
    return;
  }

  final status = readStatus(content);
  final bug = readSection(content, 'Bug');
  final rootCause = readSection(content, 'Root Cause');
  final unresolved = _readSubSection(content, 'Debug Progress', 'What is still unresolved');

  print('\n═══════════════════════════════════════');
  print('  CLAUDART SESSION STATUS');
  print('═══════════════════════════════════════');
  print('Status   : $status');
  print('Bug      : ${_truncate(bug)}');
  print('Root cause: ${_truncate(rootCause)}');
  if (status == 'debug-in-progress' || status == 'needs-suggest') {
    print('Unresolved: ${_truncate(unresolved)}');
  }
  print('');
  print('Handoff  : $handoffPath');
  print('Skills   : $skillsPath');

  print('\nNext step:');
  switch (status) {
    case 'suggest-investigating':
      print('  Run /suggest in your editor.');
    case 'ready-for-debug':
      print('  Run /debug in your editor.');
    case 'debug-in-progress':
      print('  Continue with /debug, or run /suggest if you hit a wall.');
    case 'needs-suggest':
      print('  Run /suggest in your editor — debug has a question for you.');
    default:
      print('  Run: claudart setup');
  }
  print('');
}

String _truncate(String s, {int max = 80}) {
  final single = s.replaceAll('\n', ' ').trim();
  return single.length > max ? '${single.substring(0, max)}…' : single;
}

String _readSubSection(String content, String section, String subheader) {
  final sectionContent = _extractSection(content, section);
  final match = RegExp(
    r'### ' + RegExp.escape(subheader) + r'\n+([\s\S]*?)(?=\n### |\s*$)',
  ).firstMatch(sectionContent);
  return match?.group(1)?.trim() ?? '_Nothing yet._';
}

String _extractSection(String content, String header) {
  final match = RegExp(
    r'## ' + RegExp.escape(header) + r'\n+([\s\S]*?)(?=\n## |\s*$)',
  ).firstMatch(content);
  return match?.group(1)?.trim() ?? '';
}
