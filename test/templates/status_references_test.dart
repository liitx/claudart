import 'dart:io';

import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

// Every status a template tells an agent to look for must be a real
// HandoffStatus wire value. Found by this test's first run: suggest_template
// named `suggest-needed`, which matches no variant.

const _templatesDir = 'lib/templates';
const _suggestTemplate = '$_templatesDir/suggest_template.dart';

/// Backticked tokens shaped like a status (`ready-for-debug`, `needs-suggest`).
final _statusShaped = RegExp(
  r'`((?:suggest|ready-for|debug|needs)-[a-z]+(?:-[a-z]+)?)`',
);

Iterable<String> _statusTokens(File file) =>
    _statusShaped.allMatches(file.readAsStringSync()).map((m) => m.group(1)!);

void main() {
  final wireValues = HandoffStatus.values
      .where((s) => s.isPersisted)
      .map((s) => s.value)
      .toSet();
  final templates = Directory(_templatesDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  group('status tokens in templates resolve to a HandoffStatus', () {
    for (final template in templates) {
      test(template.uri.pathSegments.last, () {
        expect(_statusTokens(template).toSet().difference(wireValues), isEmpty);
      });
    }
  });

  test('the scan still finds hand-typed status literals somewhere', () {
    // Guards the scanner against silently matching nothing.
    expect(templates.expand(_statusTokens), isNotEmpty);
  });

  test('suggest_template names statuses by interpolating HandoffStatus', () {
    final file = File(_suggestTemplate);
    final source = file.readAsStringSync();
    expect(_statusTokens(file), isEmpty);
    for (final status in [
      HandoffStatus.needsSuggest,
      HandoffStatus.readyForSuggest,
      HandoffStatus.suggestInvestigating,
      HandoffStatus.readyForDebug,
      HandoffStatus.debugInProgress,
    ]) {
      expect(source, contains('HandoffStatus.${status.name}.value'));
    }
  });
}
