// candidacy_ledger_test.dart — the candidate ledger is valid, and what it cites
// is real.
//
// `docs/candidacy/ledger.jsonl` is read with dartrix's own ledger, so a line that
// breaks a rule (an illegal move, a proof on unverified mocks, a claim wider than
// its spec) fails here. Every piece of evidence is `path :: text`: the file must
// exist and contain the text, so a ledger cannot cite a test or a line that was
// renamed or never existed. Statuses are written out below, not read from the
// ledger, so promoting a candidate is a visible edit to this file too.

import 'dart:io';

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

/// Separates a cited file from the text it must contain.
const _citationSeparator = ' :: ';

/// The candidate whose proof failed the mock audit (T7: a mock that mirrors
/// the assertion), used to show a failed audit blocks bounded and proven.
const _failedAuditCandidate = 'T7';

/// The status each candidate stands at, written out here.
const _expectedStatus = <String, CandidateStatus>{
  _failedAuditCandidate: CandidateStatus.refuted,
  'R1': CandidateStatus.bounded,
  'R1b': CandidateStatus.proven,
  'R2': CandidateStatus.bounded,
  'R3': CandidateStatus.refuted,
};

({String path, String needle}) _cite(String citation) {
  final parts = citation.split(_citationSeparator);
  return (path: parts.first, needle: parts.sublist(1).join(_citationSeparator));
}

void main() {
  final parsed = CandidateLedger.parse(
    File('docs/candidacy/ledger.jsonl').readAsStringSync(),
  );
  final entries = parsed.ledger.entries;

  group('the candidate ledger', () {
    test('every line is accepted by the ledger rules', () {
      expect(parsed.refusals, isEmpty);
    });

    group('each candidate stands where it is written to', () {
      for (final MapEntry(key: id, value: status) in _expectedStatus.entries) {
        test('$id is ${status.name}', () {
          expect(parsed.ledger.statusOf(id), status);
        });
      }

      test('no candidate is in the ledger that is not written out here', () {
        expect(entries.map((e) => e.candidateId).toSet(), _expectedStatus.keys.toSet());
      });
    });

    group('what an entry cites exists', () {
      final citations = {
        for (final entry in entries) ...{
          for (final citation in [entry.specReference, ...entry.evidence])
            citation,
        },
      };
      for (final citation in citations) {
        test(citation, () {
          final cited = _cite(citation);
          final file = File(cited.path);
          expect(file.existsSync(), isTrue, reason: '${cited.path} is missing');
          expect(file.readAsStringSync(), contains(cited.needle));
        });
      }
    });

    group('a proof on mocks that failed Phase 0 cannot be bounded or proven', () {
      for (final target in [CandidateStatus.bounded, CandidateStatus.proven]) {
        test('$_failedAuditCandidate as ${target.name} is refused: noTautologicalMock failed', () {
          final t7 = entries.where((e) => e.candidateId == _failedAuditCandidate);
          final underTest = CandidateLedger.parse(
            t7
                .where((e) => e.status != CandidateStatus.refuted)
                .map(CandidateLedger.encode)
                .join('\n'),
          ).ledger;
          final refuted = t7.last;
          final attempt = CandidateLedgerEntry(
            candidateId: refuted.candidateId,
            status: target,
            specReference: refuted.specReference,
            mockDatasetVersion: refuted.mockDatasetVersion,
            evidence: refuted.evidence,
            justification: refuted.justification,
            variantsInSpec: refuted.variantsInSpec,
            variantsCovered: refuted.variantsInSpec,
            audit: refuted.audit,
          );
          expect(underTest.append(attempt), LedgerRefusal.auditNotPassed);
        });
      }
    });
  });
}
