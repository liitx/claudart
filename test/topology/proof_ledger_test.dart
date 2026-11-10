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

  group('accepted equivalent mutants', () {
    test('a line of the registry is file, line, operator and a reason', () {
      final accepted = parseEquivalents(
        '# a comment\n'
        '\n'
        'lib/a.dart|3|greaterThan|equal values give the same maximum\n',
      );
      expect(accepted, {
        'lib/a.dart|3|greaterThan': 'equal values give the same maximum',
      });
    });

    test('a line without a reason is refused: an exemption must say why', () {
      expect(() => parseEquivalents('lib/a.dart|3|greaterThan|\n'), throwsFormatException);
    });

    test('the operator is read from the description of a mutant', () {
      expect(mutantId('line 41 greaterThan: `a > b` -> `a >= b`'), 'greaterThan');
    });

    test('a second match on a line keeps its number', () {
      expect(mutantId('line 12 equals#2: `a == b` -> `a != b`'), 'equals#2');
    });

    test('a survivor in the registry is listed as accepted, not as unguarded', () {
      final text = renderLedger(
        rows: [_mutant('line 3 minus: `a - b` -> `a + b`', verdict: ProofVerdict.missed, caughtBy: const [])],
        sources: {'lib/a.dart': 'int f(int a, int b) {\n  return 1;\n  return a - b;\n}\n'},
        lcov: const {},
        root: '/nonexistent',
        title: 'T',
        equivalents: {'lib/a.dart|3|minus': 'the branch is unreachable'},
      );
      expect(text, contains('the branch is unreachable'));
      expect(text, isNot(contains('## Lines no test guards\n\n- ')));
    });

    test('a registry entry no mutant matches is reported stale', () {
      final text = renderLedger(
        rows: [_mutant('line 2 plus: `a + b` -> `a - b`')],
        sources: {'lib/a.dart': 'x\ny\n'},
        lcov: const {},
        root: '/nonexistent',
        title: 'T',
        equivalents: {'lib/a.dart|9|minus': 'old reason'},
      );
      expect(text, contains('Registry entries no mutant matches'));
    });

    test('the survivors that are not accepted are counted apart', () {
      final rows = [
        _mutant('line 3 minus: `a` -> `b`', verdict: ProofVerdict.missed, caughtBy: const []),
        _mutant('line 4 plus: `a` -> `b`', line: 4, verdict: ProofVerdict.missed, caughtBy: const []),
      ];
      expect(
        unacceptedSurvivors(rows, {'lib/a.dart|3|minus': 'why'}).map((r) => r.line),
        [4],
      );
    });
  });

  group('why a mutant survived', () {
    final survivor = _mutant('line 3 minus: `a` -> `b`', line: 3, verdict: ProofVerdict.missed, caughtBy: const []);

    test('a line no test runs is not run', () {
      expect(survivalCause(survivor, {'lib/a.dart': {3: 0}}), SurvivalCause.notRun);
    });

    test('a line tests run but none asserts on is unasserted', () {
      expect(survivalCause(survivor, {'lib/a.dart': {3: 4}}), SurvivalCause.unasserted);
    });

    test('a line the tracefile does not mention is unmeasured', () {
      expect(survivalCause(survivor, const {}), SurvivalCause.unmeasured);
    });

    test('the family table counts each cause', () {
      final text = renderLedger(
        rows: [
          survivor,
          _mutant('line 4 plus: `a` -> `b`', line: 4, verdict: ProofVerdict.missed, caughtBy: const []),
        ],
        sources: {'lib/a.dart': 'x\ny\nz\nw\n'},
        lcov: {'lib/a.dart': {3: 0, 4: 2}},
        root: '/nonexistent',
        title: 'T',
      );
      expect(text, contains('| untouched x pure | 1 | 2 | 2 | 1 | 1 |'));
    });
  });

  group('the family of a file', () {
    test('is named in the ledger from what the file does', () {
      final text = renderLedger(
        rows: [_mutant('line 2 plus: `a` -> `b`', line: 2)],
        sources: {'lib/a.dart': 'int f(int a) {\n  return a + 1;\n}\n'},
        lcov: const {},
        root: '/nonexistent',
        title: 'T',
      );
      expect(text, contains('untouched x pure'));
    });
  });

  group('the survivor baseline', () {
    test('a file is written as its name and its survivors', () {
      expect(
        renderBaseline({'lib/b.dart': 2, 'lib/a.dart': 5, 'lib/c.dart': 0}),
        '# Surviving line mutants by file: the debt, which can only shrink.\n'
        '# Regenerate with `make ledger-baseline` after a full ledger run.\n'
        'lib/a.dart|5\n'
        'lib/b.dart|2\n',
      );
    });

    test('reading it back gives the same counts', () {
      expect(parseBaseline('# c\nlib/a.dart|5\nlib/b.dart|2\n'), {'lib/a.dart': 5, 'lib/b.dart': 2});
    });

    test('a file with more survivors than its baseline is a regression', () {
      final result = compareToBaseline({'lib/a.dart': 6}, {'lib/a.dart': 5});
      expect(result.regressions, {'lib/a.dart': (before: 5, now: 6)});
    });

    test('a file the baseline does not name starts at zero', () {
      final result = compareToBaseline({'lib/new.dart': 1}, {});
      expect(result.regressions, {'lib/new.dart': (before: 0, now: 1)});
    });

    test('fewer survivors is an improvement to write down, not a failure', () {
      final result = compareToBaseline({'lib/a.dart': 3}, {'lib/a.dart': 5});
      expect(result.regressions, isEmpty);
      expect(result.improvements, {'lib/a.dart': (before: 5, now: 3)});
    });

    test('a file that went clean is an improvement', () {
      final result = compareToBaseline({}, {'lib/a.dart': 5});
      expect(result.improvements, {'lib/a.dart': (before: 5, now: 0)});
    });

    test('the same counts change nothing', () {
      final result = compareToBaseline({'lib/a.dart': 5}, {'lib/a.dart': 5});
      expect(result.regressions, isEmpty);
      expect(result.improvements, isEmpty);
    });

    test('survivors are counted by file, leaving out the accepted ones', () {
      final rows = [
        _mutant('line 3 minus: `a` -> `b`', line: 3, verdict: ProofVerdict.missed, caughtBy: const []),
        _mutant('line 4 plus: `a` -> `b`', line: 4, verdict: ProofVerdict.missed, caughtBy: const []),
        _mutant('line 5 plus: `a` -> `b`', line: 5),
      ];
      expect(survivorsByFile(rows, {'lib/a.dart|3|minus': 'why'}), {'lib/a.dart': 1});
    });
  });

  group('what a changed line affects', () {
    const source = 'int size(int b) {\n'
        '  final c = b + 1;\n'
        '  final d = c - 1;\n'
        '  return d;\n'
        '}\n';
    final rows = [
      _mutant('line 2 plus: `a` -> `b`', line: 2, caughtBy: ['size adds one', 'size is stable']),
      _mutant('line 3 minus: `a` -> `b`', line: 3, verdict: ProofVerdict.missed, caughtBy: const []),
    ];

    test('names the tests to update for a guarded line', () {
      expect(
        describeImpact(rows, 'lib/a.dart', 2, source.split('\n')),
        contains('update: size adds one; size is stable'),
      );
    });

    test('says no test guards an unguarded line, and where the assertion goes', () {
      final text = describeImpact(rows, 'lib/a.dart', 3, source.split('\n'));
      expect(text, contains('no test fails when this line is wrong'));
      expect(text, contains('size adds one'));
    });

    test('says a line with no mutant was not measured', () {
      expect(
        describeImpact(rows, 'lib/a.dart', 4, source.split('\n')),
        contains('not measured'),
      );
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
