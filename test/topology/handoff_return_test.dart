// handoff_return_test.dart — claudart's use of dartrix's typed handoff return:
// the template says what the types say, and every entry written to the real
// candidate ledger can be routed. The checker itself is proven in dartrix.

import 'dart:convert';
import 'dart:io';

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import '../../tool/candidacy/evidence_audit.dart' show candidateLedgerPath;

void main() {
  test('the template carries the table the types render', () {
    expect(
      File('docs/templates/candidate_handoff.md').readAsStringSync(),
      contains(renderReturnTable()),
    );
  });

  group('the real ledger', () {
    final lines = File(candidateLedgerPath)
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final entry = jsonDecode(lines[i]) as Map<String, Object?>;
      test('entry ${i + 1} (${entry['candidateId']} ${entry['status']}) can be routed', () {
        expect(checkReturn(entry), isEmpty);
      });
    }
  });
}
