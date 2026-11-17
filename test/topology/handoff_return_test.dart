// handoff_return_test.dart — what an agent returns is routed by type, and the
// template says what the types say.
//
// Mock data: the real candidate ledger (every entry ever written must be
// routable) and one hand-made entry with one field broken at a time.

import 'dart:convert';
import 'dart:io';

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import '../../tool/candidacy/evidence_audit.dart' show candidateLedgerPath;
import '../../tool/candidacy/handoff_return.dart';

Map<String, Object?> _valid() => {
      'candidateId': 'X',
      'status': 'proven',
      'specReference': 'spec.md :: X',
      'mockDatasetVersion': 'mocks-1',
      'evidence': ['a.dart :: b'],
      'justification': 'Proven.',
      'variantsInSpec': ['a'],
      'variantsCovered': ['a'],
      'audit': {'mocksMatchSpec': 'passed'},
      'boundary': 'holds up to 10',
      'threshold': 0.8,
      'factors': {'boundary': 0.5},
    };

/// One broken field, the value that breaks it, and what is said of it.
const _broken = <({
  HandoffReturnField field,
  Object? value,
  ReturnFaultReason reason,
})>[
  (field: HandoffReturnField.candidateId, value: 7, reason: ReturnFaultReason.wrongShape),
  (field: HandoffReturnField.candidateId, value: ' ', reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.status, value: 'finished', reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.specReference, value: 'no separator', reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.mockDatasetVersion, value: [], reason: ReturnFaultReason.wrongShape),
  (field: HandoffReturnField.evidence, value: 'a.dart :: b', reason: ReturnFaultReason.wrongShape),
  (field: HandoffReturnField.evidence, value: ['plain'], reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.justification, value: '', reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.variantsInSpec, value: [1], reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.variantsCovered, value: 'a', reason: ReturnFaultReason.wrongShape),
  (field: HandoffReturnField.audit, value: {'noSuchCheck': 'passed'}, reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.audit, value: {'mocksMatchSpec': 'fine'}, reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.boundary, value: ' ', reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.threshold, value: 1.5, reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.threshold, value: 'high', reason: ReturnFaultReason.wrongShape),
  (field: HandoffReturnField.factors, value: {'boundary': -0.1}, reason: ReturnFaultReason.notOfKind),
  (field: HandoffReturnField.factors, value: 0.5, reason: ReturnFaultReason.wrongShape),
];

void main() {
  test('the fields are dartrix\'s ledger fields, one for one and in order', () {
    expect(
      HandoffReturnField.values.map((f) => f.ledgerField),
      LedgerField.values,
    );
  });

  test('the template carries the table the types render', () {
    expect(
      File('docs/templates/candidate_handoff.md').readAsStringSync(),
      contains(renderReturnTable()),
    );
  });

  group('checkReturn', () {
    test('a whole entry has no fault', () {
      expect(checkReturn(_valid()), isEmpty);
    });

    for (final field in HandoffReturnField.values) {
      test('${field.key} absent is '
          '${field.isRequired ? 'missing' : 'allowed'}', () {
        final returned = _valid()..remove(field.key);
        expect(
          checkReturn(returned),
          field.isRequired
              ? [(field: field, reason: ReturnFaultReason.missing)]
              : isEmpty,
        );
      });
    }

    for (final c in _broken) {
      test('${c.field.key} given ${jsonEncode(c.value)} is ${c.reason.name}', () {
        final returned = _valid()..[c.field.key] = c.value;
        expect(checkReturn(returned), [(field: c.field, reason: c.reason)]);
      });
    }

    test('every field is checked in field order', () {
      expect(
        checkReturn({}).map((f) => f.field),
        HandoffReturnField.values.where((f) => f.isRequired),
      );
    });
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
