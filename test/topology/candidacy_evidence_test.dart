// candidacy_evidence_test.dart — a candidate's "every test can fail" is derived
// from the line ledger's mutant rows, not set by reading.
//
// The derivation rules are written out as a table (not read from the tool), the
// snapshot of rows for cited lines is checked against the source it was taken
// from, and every ledger entry that records an outcome for `everyTestCanFail` must
// equal what the snapshot derives for the lines the entry cites.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/logger.dart';
import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import '../../tool/candidacy/evidence_audit.dart';
import '../../tool/proof_audit/ledger.dart' show parseEquivalents;

EvidenceRow _row(
  ProofVerdict verdict, {
  String file = 'lib/a.dart',
  int line = 1,
  String description = 'seed',
}) =>
    (
      proof: 'seed',
      file: file,
      line: line,
      description: description,
      verdict: verdict,
    );

/// The outcome each set of verdicts derives, written out here.
const _derivation = <({
  String name,
  List<ProofVerdict> verdicts,
  ProofAuditOutcome outcome,
})>[
  (name: 'no rows', verdicts: [], outcome: ProofAuditOutcome.notChecked),
  (
    name: 'only a mutant that does not compile',
    verdicts: [ProofVerdict.invalid],
    outcome: ProofAuditOutcome.notChecked,
  ),
  (
    name: 'a caught mutant',
    verdicts: [ProofVerdict.caught],
    outcome: ProofAuditOutcome.passed,
  ),
  (
    name: 'a caught mutant and one that does not compile',
    verdicts: [ProofVerdict.caught, ProofVerdict.invalid],
    outcome: ProofAuditOutcome.passed,
  ),
  (
    name: 'a mutant no test failed on',
    verdicts: [ProofVerdict.missed],
    outcome: ProofAuditOutcome.failed,
  ),
  (
    name: 'a caught mutant and one no test failed on',
    verdicts: [ProofVerdict.caught, ProofVerdict.missed],
    outcome: ProofAuditOutcome.failed,
  ),
  (
    name: 'a missed mutant beside one that does not compile',
    verdicts: [ProofVerdict.invalid, ProofVerdict.missed],
    outcome: ProofAuditOutcome.failed,
  ),
];

EvidenceRow _snapshotRow(Map<String, dynamic> json) => (
      proof: json['proof'] as String,
      file: json['file'] as String,
      line: json['line'] as int,
      description: json['description'] as String,
      verdict: ProofVerdict.values.byName(json['verdict'] as String),
    );

String _fakeSource(String path) => 'first\nthe needle here\nthird\nneedle again';

void main() {
  group('everyTestCanFailFrom', () {
    for (final scenario in _derivation) {
      test('${scenario.name} is ${scenario.outcome.name}', () {
        expect(
          everyTestCanFailFrom([for (final v in scenario.verdicts) _row(v)]),
          scenario.outcome,
        );
      });
    }

    // A mutant the registry names (file, line, operator) is the same program, so
    // it is not judged; one that differs in any of the three still counts.
    group('with an accepted equivalent registered for lib/a.dart line 1 greaterThan', () {
      final registry = parseEquivalents('lib/a.dart|1|greaterThan|same result');
      const named = 'line 1 greaterThan: x';
      final cases = <({
        String name,
        List<EvidenceRow> rows,
        ProofAuditOutcome outcome,
      })>[
        (
          name: 'the named mutant missed beside a caught one is passed',
          rows: [
            _row(ProofVerdict.missed, description: named),
            _row(ProofVerdict.caught, line: 2),
          ],
          outcome: ProofAuditOutcome.passed,
        ),
        (
          name: 'the named mutant alone is not checked',
          rows: [_row(ProofVerdict.missed, description: named)],
          outcome: ProofAuditOutcome.notChecked,
        ),
        (
          name: 'another operator on the line is failed',
          rows: [_row(ProofVerdict.missed, description: 'line 1 lessThan: x')],
          outcome: ProofAuditOutcome.failed,
        ),
        (
          name: 'the same operator on another line is failed',
          rows: [_row(ProofVerdict.missed, line: 2, description: 'line 2 greaterThan: x')],
          outcome: ProofAuditOutcome.failed,
        ),
        (
          name: 'the same operator on another file is failed',
          rows: [_row(ProofVerdict.missed, file: 'lib/b.dart', description: named)],
          outcome: ProofAuditOutcome.failed,
        ),
      ];
      for (final scenario in cases) {
        test(scenario.name, () {
          expect(
            everyTestCanFailFrom(scenario.rows, acceptedEquivalents: registry),
            scenario.outcome,
          );
        });
      }
    });
  });

  group('evidenceRows', () {
    Map<String, dynamic> logged(String proof, String fault, String verdict) => {
          'proof': proof,
          'fault': fault,
          'sourceFile': 'lib/a.dart',
          'sourceLine': 7,
          'verdict': verdict,
        };

    test('keeps a matrix fault and a mutant alike', () {
      expect(
        evidenceRows([
          logged('closureEvidence', 'one', 'caught'),
          logged('mutants:lib/a.dart', 'two', 'missed'),
        ]).map((r) => r.proof),
        ['closureEvidence', 'mutants:lib/a.dart'],
      );
    });

    test('leaves out the audit checking itself', () {
      expect(evidenceRows([logged('control', 'a comment appended', 'missed')]),
          isEmpty);
    });

    test('the latest verdict of a fault wins', () {
      expect(
        evidenceRows([
          logged('closureEvidence', 'one', 'missed'),
          logged('closureEvidence', 'one', 'caught'),
        ]).map((r) => r.verdict),
        [ProofVerdict.caught],
      );
    });

    test('the same fault text under another proof is another row', () {
      expect(
        evidenceRows([
          logged('closureEvidence', 'one', 'caught'),
          logged('other', 'one', 'caught'),
        ]),
        hasLength(2),
      );
    });
  });

  group('citedLines', () {
    test('every line holding the cited text', () {
      expect(
        citedLines('lib/x.dart :: needle', _fakeSource).map((c) => c.line),
        [2, 4],
      );
    });

    test('a citation outside lib cites no code', () {
      expect(citedLines('test/x_test.dart :: needle', _fakeSource), isEmpty);
    });

    test('text that is not there cites nothing', () {
      expect(citedLines('lib/x.dart :: absent', _fakeSource), isEmpty);
    });

    test('a separator inside the cited text stays part of it', () {
      expect(
        citedLines('lib/x.dart :: the needle here', _fakeSource).map((c) => c.line),
        [2],
      );
    });
  });

  group('rowsOnCitedLines', () {
    const cited = [(file: 'lib/a.dart', line: 3, text: '')];

    test('keeps a row on a cited line', () {
      expect(rowsOnCitedLines([_row(ProofVerdict.caught, line: 3)], cited),
          hasLength(1));
    });

    test('drops a row on another line', () {
      expect(rowsOnCitedLines([_row(ProofVerdict.caught, line: 4)], cited),
          isEmpty);
    });

    test('drops a row of another file on the same line number', () {
      expect(
          rowsOnCitedLines(
              [_row(ProofVerdict.caught, file: 'lib/b.dart', line: 3)], cited),
          isEmpty);
    });
  });

  group('the snapshot of mutant rows', () {
    final snapshot = [
      for (final line in File(evidenceRowsPath).readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ];

    test('is not empty', () {
      expect(snapshot, isNotEmpty);
    });

    final lines = {
      for (final row in snapshot)
        '${row['file']}:${row['line']}': (row['file'] as String, row['line'] as int, row['lineText'] as String),
    };
    for (final MapEntry(key: where, value: (file, line, text)) in lines.entries) {
      test('$where still reads as it did when the mutants ran', () {
        expect(File(file).readAsLinesSync()[line - 1], text);
      });
    }
  });

  group('what the ledger records matches what the rows derive', () {
    final parsed = CandidateLedger.parse(File(candidateLedgerPath).readAsStringSync());
    final equivalents = parseEquivalents(
      File('tool/proof_audit/accepted_equivalents.txt').readAsStringSync(),
    );
    final rows = [
      for (final line in File(evidenceRowsPath).readAsLinesSync())
        if (line.trim().isNotEmpty) _snapshotRow(jsonDecode(line) as Map<String, dynamic>),
    ];

    for (final entry in parsed.ledger.entries) {
      final recorded = entry.audit.toJson()[ProofAuditCheck.everyTestCanFail.name];
      if (recorded == null) continue;
      test('${entry.candidateId} ${entry.status.name}: everyTestCanFail', () {
        final cited = [
          for (final citation in entry.evidence)
            ...citedLines(citation, (p) => File(p).readAsStringSync()),
        ];
        expect(
          everyTestCanFailFrom(
            rowsOnCitedLines(rows, cited),
            acceptedEquivalents: equivalents,
          ).name,
          recorded,
        );
      });
    }
  });
}
