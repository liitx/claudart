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
import '../../tool/proof_audit/ledger.dart';

MutantRow _row(ProofVerdict verdict, {String file = 'lib/a.dart', int line = 1}) =>
    (
      file: file,
      line: line,
      description: 'seed',
      verdict: verdict,
      tier: 1,
      caughtBy: const [],
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
    final rows = [
      for (final line in File(evidenceRowsPath).readAsLinesSync())
        if (line.trim().isNotEmpty)
          (
            file: (jsonDecode(line) as Map<String, dynamic>)['file'] as String,
            line: (jsonDecode(line) as Map<String, dynamic>)['line'] as int,
            description: (jsonDecode(line) as Map<String, dynamic>)['description'] as String,
            verdict: ProofVerdict.values.byName(
                (jsonDecode(line) as Map<String, dynamic>)['verdict'] as String),
            tier: 1,
            caughtBy: const <String>[],
          ),
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
          everyTestCanFailFrom(rowsOnCitedLines(rows, cited)).name,
          recorded,
        );
      });
    }
  });
}
