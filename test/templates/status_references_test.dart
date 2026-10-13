import 'dart:io';

import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

// Every status a template tells an agent to look for must be a real
// HandoffStatus wire value. Found by this test's first run: suggest_template
// named `suggest-needed`, which matches no variant.

const _templatesDir = 'lib/templates';

/// Backticked tokens shaped like a status (`ready-for-debug`, `needs-suggest`).
final _statusShaped = RegExp(r'`((?:suggest|ready-for|debug|needs)-[a-z]+(?:-[a-z]+)?)`');

void main() {
  final wireValues = HandoffStatus.values.where((s) => s.isPersisted).map((s) => s.value).toSet();
  final templates = Directory(_templatesDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  group('status tokens in templates resolve to a HandoffStatus', () {
    for (final template in templates) {
      test(template.uri.pathSegments.last, () {
        final mentioned = _statusShaped
            .allMatches(template.readAsStringSync())
            .map((m) => m.group(1)!)
            .toSet();
        expect(mentioned.difference(wireValues), isEmpty);
      });
    }
  });

  test('the scan still finds hand-typed status literals somewhere (it is not matching nothing)', () {
    final all = templates.expand((f) => _statusShaped.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    expect(all, isNotEmpty);
  });

  test('suggest_template routes by interpolating HandoffStatus, with no hand-typed status literals', () {
    final text = File('$_templatesDir/suggest_template.dart').readAsStringSync();
    expect(_statusShaped.allMatches(text), isEmpty);
    for (final status in [
      HandoffStatus.needsSuggest,
      HandoffStatus.readyForSuggest,
      HandoffStatus.suggestInvestigating,
      HandoffStatus.readyForDebug,
      HandoffStatus.debugInProgress,
    ]) {
      expect(text, contains('HandoffStatus.${status.name}.value'));
    }
  });
}
