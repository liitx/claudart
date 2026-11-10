// The ledger's own checks: it must read the rows right, find the declaration a
// line sits in, and name the existing tests a missing assertion belongs with.
// A ledger that mislabels a line would send a test to the wrong place.

import 'package:claudart/logging/logger.dart';
import 'package:test/test.dart';

import '../../tool/proof_audit/ledger.dart';

Map<String, dynamic> _row(
  String description, {
  String file = 'lib/a.dart',
  int line = 3,
  String verdict = 'caught',
  int tier = 1,
  List<String> caughtBy = const ['test one'],
}) =>
    {
      'proof': '$mutantProofPrefix$file',
      'fault': description,
      'sourceLine': line,
      'verdict': verdict,
      'tier': tier,
      'caughtBy': caughtBy,
    };

MutantRow _mutant(
  String description, {
  int line = 3,
  ProofVerdict verdict = ProofVerdict.caught,
  int tier = 1,
  List<String> caughtBy = const ['test one'],
}) =>
    (
      file: 'lib/a.dart',
      line: line,
      description: description,
      verdict: verdict,
      tier: tier,
      caughtBy: caughtBy,
    );

void main() {
  group('reading the rows', () {
    test('a row of another proof is not a mutant', () {
      expect(mutantRows([_row('x')..['proof'] = 'transitionTable']), isEmpty);
    });

    test('the latest row for a mutant is the one that counts', () {
      final rows = mutantRows([
        _row('line 3 equals', verdict: 'invalid', caughtBy: const []),
        _row('line 3 equals', verdict: 'caught'),
      ]);
      expect(rows.single.verdict, ProofVerdict.caught);
    });

    test('the file is read from the proof name', () {
      expect(mutantRows([_row('x', file: 'lib/src/b.dart')]).single.file, 'lib/src/b.dart');
    });
  });

  group('the declaration a line sits in', () {
    const source = 'class Box {\n'
        '  final int a;\n'
        '\n'
        '  int size(int b) {\n'
        '    final c = b + 1;\n'
        '    return c;\n'
        '  }\n'
        '\n'
        '  bool get empty => a == 0;\n'
        '}\n'
        '\n'
        'int top(int x) => x + 1;\n';
    final lines = source.split('\n');

    test('a line in a method is in that method', () {
      expect(enclosingDeclaration(lines, 5), 'size');
    });

    test('a line in a getter is in that getter', () {
      expect(enclosingDeclaration(lines, 9), 'empty');
    });

    test('a top-level function is its own declaration', () {
      expect(enclosingDeclaration(lines, 12), 'top');
    });

    test('a statement keyword is never taken for a declaration', () {
      const guarded = 'int top(List<int> xs) {\n'
          '  if (xs.isEmpty) return 1;\n'
          '  return 2;\n'
          '}\n';
      expect(enclosingDeclaration(guarded.split('\n'), 2), 'top');
    });

    test('a named constructor is its own declaration', () {
      const factory = 'class P {\n'
          '  bool get ok => true;\n'
          '\n'
          '  factory P.fromJson(Map<String, dynamic> json) {\n'
          '    return P._(json[\'line\'] as int);\n'
          '  }\n'
          '}\n';
      expect(enclosingDeclaration(factory.split('\n'), 5), 'P.fromJson');
    });

    test('a field is in the class that holds it', () {
      expect(enclosingDeclaration(lines, 2), 'Box');
    });
  });

  group('the tracefile', () {
    test('hit counts are read by line and file, from the lib segment', () {
      final hits = lineHits('SF:/home/x/app/lib/a.dart\nDA:1,3\nDA:2,0\nend_of_record\n');
      expect(hits['lib/a.dart'], {1: 3, 2: 0});
    });
  });

  group('tests that kill the same mutants', () {
    test('two tests with the same three kills are grouped', () {
      final rows = [
        _mutant('m1', caughtBy: ['a', 'b']),
        _mutant('m2', caughtBy: ['a', 'b']),
        _mutant('m3', caughtBy: ['a', 'b']),
      ];
      expect(identicalKillers(rows).single.tests, ['a', 'b']);
    });

    test('tests that differ on one mutant are not grouped', () {
      final rows = [
        _mutant('m1', caughtBy: ['a', 'b']),
        _mutant('m2', caughtBy: ['a', 'b']),
        _mutant('m3', caughtBy: ['a']),
      ];
      expect(identicalKillers(rows), isEmpty);
    });

    test('a pair that kills fewer than the minimum is left out', () {
      final rows = [_mutant('m1', caughtBy: ['a', 'b'])];
      expect(identicalKillers(rows), isEmpty);
    });
  });

  group('the tests that guard a line', () {
    test('are the ones that failed for a mutant of it, sorted and once', () {
      final rows = [
        _mutant('m1', line: 4, caughtBy: ['b', 'a']),
        _mutant('m2', line: 4, caughtBy: ['a']),
        _mutant('m3', line: 9, caughtBy: ['z']),
      ];
      expect(testsGuarding(rows, 'lib/a.dart', 4), ['a', 'b']);
    });

    test('are none for a line nothing guards', () {
      expect(testsGuarding([_mutant('m1', line: 4)], 'lib/a.dart', 5), isEmpty);
    });
  });

  group('the ledger', () {
    const source = 'int size(int b) {\n'
        '  final c = b + 1;\n'
        '  final d = c - 1;\n'
        '  return d;\n'
        '}\n';

    String ledger(List<MutantRow> rows, {Map<String, Map<int, int>> lcov = const {}}) =>
        renderLedger(
          rows: rows,
          sources: {'lib/a.dart': source},
          lcov: lcov,
          root: '/nonexistent',
          title: 'T',
        );

    test('names the tests that guard the neighbors of a surviving line', () {
      final text = ledger([
        _mutant('line 2 plus', line: 2, caughtBy: ['size adds one']),
        _mutant('line 3 minus', line: 3, verdict: ProofVerdict.missed, caughtBy: const []),
      ]);
      expect(text, contains('add to the tests that guard `size`: size adds one'));
    });

    test('says when no test guards anything in the declaration', () {
      final text = ledger([
        _mutant('line 3 minus', line: 3, verdict: ProofVerdict.missed, caughtBy: const []),
      ]);
      expect(text, contains('no test guards anything in `size`'));
    });

    test('says a surviving line no test reaches is not run', () {
      final text = ledger(
        [_mutant('line 3 minus', line: 3, verdict: ProofVerdict.missed, caughtBy: const [])],
        lcov: {'lib/a.dart': {3: 0}},
      );
      expect(text, contains('no, no test reaches this line'));
    });

    test('says which tests were left out of the wider run', () {
      final text = renderLedger(
        rows: [_mutant('m1', line: 2)],
        sources: {'lib/a.dart': source},
        lcov: const {},
        root: '/nonexistent',
        title: 'T',
        excludedTests: ['test/topology/docs_test.dart'],
      );
      expect(text, contains('`test/topology/docs_test.dart`'));
    });

    test('lists a line only the wider suite guards', () {
      final text = ledger([_mutant('line 2 plus', line: 2, tier: 2, caughtBy: ['far away test'])]);
      expect(text, contains('far away test'));
    });

    test('counts a mutant by how it ended', () {
      final text = ledger([
        _mutant('m1', line: 2),
        _mutant('m2', line: 3, verdict: ProofVerdict.missed, caughtBy: const []),
      ]);
      expect(text, contains('| 2 | 1 | 0 | 1 | 0 |'));
    });
  });
}
