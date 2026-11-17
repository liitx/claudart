// candidacy_index_test.dart — the candidate index is the ledger, written out.
//
// The page an agent reads instead of the ledger must say what the ledger says. The
// renderer is checked on a small ledger whose page is written out by hand, and the
// committed page must equal what the renderer makes of the real ledger.

import 'dart:convert';
import 'dart:io';

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import '../../tool/candidacy/index.dart';

String _line(Map<String, Object?> entry) => jsonEncode(entry);

Map<String, Object?> _entry(
  String id,
  String status, {
  List<String> evidence = const [],
  List<String> covered = const [],
}) =>
    {
      'candidateId': id,
      'status': status,
      'specReference': 'spec.md :: $id',
      'mockDatasetVersion': 'mocks-1',
      'evidence': evidence,
      'justification': 'Stated: $id holds.',
      'variantsInSpec': ['a', 'b'],
      'variantsCovered': covered,
      'audit': <String, Object?>{},
    };

void main() {
  group('renderCandidateIndex', () {
    test('writes counts, flags, and one block per candidate in first-seen order',
        () {
      final ledger = CandidateLedger.parse([
        _line(_entry('X', 'candidate')),
        _line(_entry('Y', 'candidate')),
        _line(_entry('Y', 'underTest', evidence: ['spec.md :: Y'], covered: ['a'])),
      ].join('\n')).ledger;
      expect(
        renderCandidateIndex(ledger),
        '# Candidate index\n'
        '\n'
        'Generated from `docs/candidacy/ledger.jsonl` by '
        '`dart run tool/candidacy/index.dart`; a test fails when it differs. '
        'Confidence is under the initial weights, which are an assumption.\n'
        '\n'
        '## By status\n'
        '\n'
        '- candidate: X\n'
        '- underTest: Y\n'
        '- proven: none\n'
        '- bounded: none\n'
        '- refuted: none\n'
        '- axiom: none\n'
        '\n'
        'Flagged (confidence stalled or dropped): none\n'
        '\n'
        '## X: candidate\n'
        '\n'
        '- Statement: Stated: X holds.\n'
        '- Spec: spec.md :: X\n'
        '- Mocks: mocks-1\n'
        '- Variants covered: 0 of 2\n'
        '- Boundary: not stated\n'
        '- Confidence: none\n'
        '- History: candidate\n'
        '- Evidence:\n'
        '  - none\n'
        '\n'
        '## Y: underTest\n'
        '\n'
        '- Statement: Stated: Y holds.\n'
        '- Spec: spec.md :: Y\n'
        '- Mocks: mocks-1\n'
        '- Variants covered: 1 of 2\n'
        '- Boundary: not stated\n'
        '- Confidence: none\n'
        '- History: candidate -> underTest\n'
        '- Evidence:\n'
        '  - spec.md :: Y\n',
      );
    });
  });

  test('the committed index is what the ledger renders', () {
    final ledger = CandidateLedger.parse(
      File('docs/candidacy/ledger.jsonl').readAsStringSync(),
    ).ledger;
    expect(File(candidacyIndexPath).readAsStringSync(), renderCandidateIndex(ledger));
  });

  group('the candidate handoff template', () {
    final template = File('docs/templates/candidate_handoff.md').readAsStringSync();

    for (final status in CandidateStatus.values) {
      test('names the status ${status.name}', () {
        expect(template, contains('`${status.name}`'));
      });
    }
  });
}
