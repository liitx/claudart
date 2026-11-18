// gap_register_test.dart — the gap register and its family table agree.
//
// docs/methodical_refactor.md lists every known gap with an id and a name, and
// places each one in a family (state role x reach layer) or names the new
// variant it needs. This fails when a gap has no family row, a row has no gap,
// an id or name repeats, a family is not a real StateRole x ReachLayer pair,
// or a "new" variant is not among the proposals.

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/topology_family.dart';

const _docPath = 'docs/methodical_refactor.md';
const _registerHeading = '## Gap register';
const _classificationHeading = '## Gap to family';
const _proposalsHeading = '### Proposed new variants';
const _stageRecordsHeading = '## Stage records';
const _existingVerdict = 'existing';
const _newVerdictPrefix = 'new: ';
const _noFamily = '—';
const _familySeparator = ';';
const _pairSeparator = ' x ';

final _registerRow = RegExp(r'^\| ([A-Z]+\d+) \| `(\w+)` \|', multiLine: true);
final _classificationRow = RegExp(
  r'^\| ([A-Z]+\d+) \| ([^|]+?) \| (existing|new: \w+) \|$',
  multiLine: true,
);
final _proposalRow = RegExp(r'^\| `([\w.]+)` \|', multiLine: true);

/// The text of [doc] from [from] up to [to] (or to the end).
String section(String doc, String from, [String? to]) {
  final start = doc.indexOf(from);
  if (start < 0) return '';
  final end = to == null ? -1 : doc.indexOf(to, start + from.length);
  return end < 0 ? doc.substring(start) : doc.substring(start, end);
}

/// The (id, name) of every register row in [text], in order.
List<(String, String)> registerEntries(String text) => [
      for (final match in _registerRow.allMatches(text))
        (match.group(1)!, match.group(2)!),
    ];

/// The (id, family, verdict) of every classification row in [text].
List<(String, String, String)> classificationEntries(String text) => [
      for (final match in _classificationRow.allMatches(text))
        (match.group(1)!, match.group(2)!, match.group(3)!),
    ];

/// The names in the proposals table of [text].
Set<String> proposalNames(String text) => {
      for (final match in _proposalRow.allMatches(text)) match.group(1)!,
    };

/// Whether [pair] is `<StateRole> x <ReachLayer>` with both real variants.
bool isRealFamily(String pair) {
  final parts = pair.trim().split(_pairSeparator);
  if (parts.length != 2) return false;
  final roles = StateRole.values.map((v) => v.name);
  final layers = ReachLayer.values.map((v) => v.name);
  return roles.contains(parts[0]) && layers.contains(parts[1]);
}

void main() {
  group('registerEntries', () {
    test('reads each id and name', () {
      expect(
        registerEntries('| S1 | `statusStreamMissing` | gap |\n'
            '| Id | Name |\n'
            '| D4 | `strictModeOff` | gap |'),
        [('S1', 'statusStreamMissing'), ('D4', 'strictModeOff')],
      );
    });
  });

  group('classificationEntries', () {
    test('reads an existing family and a new variant', () {
      expect(
        classificationEntries(
          '| S1 | drivesState x pure | existing |\n'
          '| S4 | — | new: TriggerSource |',
        ),
        [
          ('S1', 'drivesState x pure', 'existing'),
          ('S4', '—', 'new: TriggerSource'),
        ],
      );
    });
  });

  group('isRealFamily', () {
    test('accepts a real pair', () {
      expect(isRealFamily('drivesState x processBound'), isTrue);
    });

    test('rejects an unknown role', () {
      expect(isRealFamily('listens x processBound'), isFalse);
    });

    test('rejects an unknown layer', () {
      expect(isRealFamily('drivesState x everywhere'), isFalse);
    });
  });

  group('the register in $_docPath', () {
    final doc = File(_docPath).readAsStringSync();
    final register = registerEntries(
      section(doc, _registerHeading, _classificationHeading),
    );
    final classification = classificationEntries(
      section(doc, _classificationHeading, _stageRecordsHeading),
    );
    final proposals = proposalNames(
      section(doc, _proposalsHeading, _stageRecordsHeading),
    );

    test('has at least one gap', () {
      expect(register, isNotEmpty);
    });

    test('uses no id twice', () {
      final ids = register.map((entry) => entry.$1).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('uses no name twice', () {
      final names = register.map((entry) => entry.$2).toList();
      expect(names.toSet().length, names.length);
    });

    test('places every gap in a family row, and every row has a gap', () {
      expect(
        classification.map((row) => row.$1).toSet(),
        register.map((entry) => entry.$1).toSet(),
      );
    });

    test('has one family row per gap', () {
      final ids = classification.map((row) => row.$1).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every existing family is a real role x reach pair', () {
      for (final row in classification.where((r) => r.$3 == _existingVerdict)) {
        for (final pair in row.$2.split(_familySeparator)) {
          expect(isRealFamily(pair), isTrue, reason: '${row.$1}: $pair');
        }
      }
    });

    test('a new variant has no family and is a proposal', () {
      for (final row in classification.where((r) => r.$3 != _existingVerdict)) {
        expect(row.$2, _noFamily, reason: row.$1);
        expect(
          proposals,
          contains(row.$3.substring(_newVerdictPrefix.length)),
          reason: row.$1,
        );
      }
    });
  });
}
