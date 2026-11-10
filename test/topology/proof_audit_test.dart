// The proof audit's own checks: its faults are the whole table, its reading of
// a test run is right, and a fault it builds is the one change it says it is.
// An audit that cannot be trusted would only move the doubt.

import 'dart:io';

import 'package:claudart/io/file_io.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../../tool/proof_audit/changed_lines.dart';
import '../../tool/proof_audit/closure_faults.dart';
import '../../tool/proof_audit/command_faults.dart';
import '../../tool/proof_audit/fault.dart';
import '../../tool/proof_audit/listener_faults.dart';
import '../../tool/proof_audit/mutant_faults.dart';
import '../../tool/proof_audit/providers.dart';
import '../../tool/proof_audit/report.dart';
import '../../tool/proof_audit/runner.dart';
import '../../tool/proof_audit/table_faults.dart';

class _ChangesTheText extends SeededFault {
  const _ChangesTheText();

  @override
  String get proof => 'test';

  @override
  String get description => 'changes the text';

  @override
  String get sourceFile => 'lib/session/session_state.dart';

  @override
  int get sourceLine => 1;

  @override
  String apply(String source) => 'changed';
}

void main() {
  final faults = const TransitionTableFaults().faults('.');
  final source = File('lib/session/session_state.dart').readAsStringSync();

  group('the table faults', () {
    test('are eight for each of the cells', () {
      final cellCount = HandoffStatus.values.length * HandoffEvent.values.length;
      expect(faults, hasLength(cellCount * 8));
    });

    test('change a cell to a value it does not already hold', () {
      expect(
        faults.whereType<TableCellFault>().where((f) => f.current == f.replacement),
        isEmpty,
      );
    });

    test('stand for a line inside the real switch', () {
      final switchStart =
          source.split('\n').indexWhere((l) => l.contains('HandoffStatus? after('));
      expect(faults.every((f) => f.sourceLine > switchStart), isTrue);
    });

    test('are described in the form the report reads back', () {
      expect(faults.every((f) => cellFaultPattern.hasMatch(f.description)), isTrue);
    });
  });

  group('a table fault applied', () {
    final fault = faults.whereType<TableCellFault>().firstWhere(
          (f) =>
              f.status == HandoffStatus.noHandoff &&
              f.event == HandoffEvent.setup &&
              f.replacement == null,
        );
    final applied = fault.apply(source);

    test('writes the one changed cell as null', () {
      expect(applied,
          contains('(HandoffStatus.noHandoff, HandoffEvent.setup): null,'));
    });

    test('keeps every other cell as the real table has it', () {
      final unchanged = faults.whereType<TableCellFault>().first.cells.entries
          .where((e) => e.key != (HandoffStatus.noHandoff, HandoffEvent.setup));
      for (final entry in unchanged) {
        final value = entry.value == null
            ? 'null'
            : 'HandoffStatus.${entry.value!.name}';
        expect(
          applied,
          contains('(HandoffStatus.${entry.key.$1.name}, '
              'HandoffEvent.${entry.key.$2.name}): $value,'),
        );
      }
    });

    test('replaces the real switch with a lookup', () {
      expect(applied, isNot(contains('HandoffEvent.setup => switch (this)')));
      expect(applied, contains('_auditedCells[(this, event)]'));
    });
  });

  group('reading a test run', () {
    const start = '{"type":"testStart","test":{"id":1,"name":"a proof"}}\n';

    test('the file of a failing test is recorded', () {
      final judgement = judgeTestRun(
        '{"type":"suite","suite":{"id":0,"path":"test/a_test.dart"}}\n'
        '{"type":"testStart","test":{"id":1,"name":"a proof","suiteID":0}}\n'
        '{"type":"testDone","testID":1,"result":"failure"}\n',
        1,
      );
      expect(judgement.failedFiles, ['test/a_test.dart']);
    });

    test('a file that threw while loading is recorded by its path', () {
      final judgement = judgeTestRun(
        '{"type":"testStart","test":{"id":2,"name":"loading test/x_test.dart"}}\n'
        '{"type":"error","testID":2,"error":"RangeError","isFailure":false}\n'
        '{"type":"testDone","testID":2,"result":"error"}\n',
        1,
      );
      expect(judgement.failedFiles, ['test/x_test.dart']);
    });

    test('a passing file is not recorded', () {
      final judgement = judgeTestRun(
        '{"type":"suite","suite":{"id":0,"path":"test/a_test.dart"}}\n'
        '{"type":"testStart","test":{"id":1,"name":"fine","suiteID":0}}\n'
        '{"type":"testDone","testID":1,"result":"success"}\n',
        0,
      );
      expect(judgement.failedFiles, isEmpty);
    });

    test('a failing test is a catch, named by its title', () {
      final judgement = judgeTestRun(
        '$start{"type":"testDone","testID":1,"result":"failure"}\n',
        1,
      );
      expect(judgement.failed, ['a proof']);
      expect(judgement.invalid, isFalse);
    });

    test('an erroring test is a catch too', () {
      final judgement = judgeTestRun(
        '$start{"type":"testDone","testID":1,"result":"error"}\n',
        1,
      );
      expect(judgement.failed, ['a proof']);
    });

    test('passing tests catch nothing', () {
      final judgement = judgeTestRun(
        '$start{"type":"testDone","testID":1,"result":"success"}\n',
        0,
      );
      expect(judgement.failed, isEmpty);
      expect(judgement.invalid, isFalse);
    });

    test('a suite that cannot load is invalid, not a catch', () {
      final judgement = judgeTestRun(
        '{"type":"testStart","test":{"id":2,"name":"loading test/x_test.dart"}}\n'
        '{"type":"testDone","testID":2,"result":"error"}\n',
        1,
      );
      expect(judgement.invalid, isTrue);
      expect(judgement.failed, isEmpty);
    });

    test('a suite that throws while loading is a catch, named for the file', () {
      final judgement = judgeTestRun(
        '{"type":"testStart","test":{"id":2,"name":"loading test/x_test.dart"}}\n'
        '{"type":"error","testID":2,"error":"Failed to load \\"test/x_test.dart\\": RangeError (length): Invalid value","isFailure":false}\n'
        '{"type":"testDone","testID":2,"result":"error"}\n',
        1,
      );
      expect(judgement.invalid, isFalse);
      expect(judgement.failed, ['test/x_test.dart fails while loading']);
    });

    test('a suite that does not compile is invalid, whatever its text says', () {
      final judgement = judgeTestRun(
        '{"type":"testStart","test":{"id":2,"name":"loading test/x_test.dart"}}\n'
        '{"type":"error","testID":2,"error":"Failed to load \\"test/x_test.dart\\": Compilation failed","isFailure":false}\n'
        '{"type":"testDone","testID":2,"result":"error"}\n',
        1,
      );
      expect(judgement.invalid, isTrue);
      expect(judgement.failed, isEmpty);
    });

    test('a compiler diagnostic in the error is a failure to compile', () {
      final judgement = judgeTestRun(
        '{"type":"testStart","test":{"id":2,"name":"loading test/x_test.dart"}}\n'
        '{"type":"error","testID":2,"error":"lib/a.dart:3:5: Error: Expected an identifier.","isFailure":false}\n'
        '{"type":"testDone","testID":2,"result":"error"}\n',
        1,
      );
      expect(judgement.invalid, isTrue);
    });

    test('a failing exit with no failed test is invalid', () {
      expect(judgeTestRun('', 1).invalid, isTrue);
    });

    test('an event with raw output in front of it is still read', () {
      final judgement = judgeTestRun(
        '$start  \x1B[36m⠋\x1B[0m  Categorizing intent'
        '{"type":"testDone","testID":1,"result":"failure"}\n',
        1,
      );
      expect(judgement.failed, ['a proof']);
    });

    test('a test start with raw output in front of it still names the test', () {
      final judgement = judgeTestRun(
        'Writing files…{"type":"testStart","test":{"id":1,"name":"a proof"}}\n'
        '{"type":"testDone","testID":1,"result":"failure"}\n',
        1,
      );
      expect(judgement.failed, ['a proof']);
    });

    test('raw output after an event is ignored', () {
      final judgement = judgeTestRun(
        '$start{"type":"testDone","testID":1,"result":"failure"}  \x1B[2Kdone\n',
        1,
      );
      expect(judgement.failed, ['a proof']);
    });

    test('a failure with no recorded start is named for what is missing', () {
      final judgement = judgeTestRun(
        '{"type":"testDone","testID":9,"result":"failure"}\n',
        1,
      );
      expect(judgement.failed, [noRecordedStartName]);
    });

    test('lines that are not JSON events are ignored', () {
      expect(judgeTestRun('not json\n{broken\n', 0).failed, isEmpty);
    });
  });

  group('a fault whose test run showed nothing', () {
    late Directory scratch;
    late SessionLogger logger;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('proof_audit_test_');
      Directory('${scratch.path}/lib/session').createSync(recursive: true);
      File('${scratch.path}/lib/session/session_state.dart')
          .writeAsStringSync('original');
      logger = SessionLogger.plain(
        io: const RealFileIO(),
        workspacePath: scratch.path,
      );
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    const invalid = TestJudgement(failed: [], invalid: true);
    const caught = TestJudgement(failed: ['a proof'], invalid: false);
    const passed = TestJudgement(failed: [], invalid: false);
    const hung = TestJudgement(failed: [], invalid: true, timedOut: true);

    Future<FaultResult> checkWith(List<TestJudgement> answers) {
      final queue = [...answers];
      final runner = AuditRunner(
        scratchRoot: scratch.path,
        logger: logger,
        runTests: (_) async => queue.removeAt(0),
      );
      return runner.check(const TransitionTableFaults(), const _ChangesTheText());
    }

    test('is run again once, and the retry is counted', () async {
      final result = await checkWith([invalid, caught]);
      expect(result.verdict, ProofVerdict.caught);
      expect(result.attempts, 2);
    });

    test('is invalid when the retry shows nothing either', () async {
      final result = await checkWith([invalid, invalid]);
      expect(result.verdict, ProofVerdict.invalid);
      expect(result.attempts, 2);
    });

    test('with no tier-one tests goes straight to the wider run', () async {
      final calls = <List<String>>[];
      final runner = AuditRunner(
        scratchRoot: scratch.path,
        logger: logger,
        runTests: (tests) async {
          calls.add(tests);
          return caught;
        },
      );
      final result = await runner.check(
        const FileMutantFaults(file: 'lib/a.dart', tierOne: [], tierTwo: ['test']),
        const _ChangesTheText(),
      );
      expect(calls, hasLength(1));
      expect(result.tier, 2);
      expect(result.verdict, ProofVerdict.caught);
    });

    test('is not run again when the run hit its time limit', () async {
      final result = await checkWith([hung, caught]);
      expect(result.verdict, ProofVerdict.invalid);
      expect(result.attempts, 1);
    });

    test('is not run again when the first run caught it', () async {
      final result = await checkWith([caught]);
      expect(result.attempts, 1);
    });

    test('is not run again when the first run passed: that is a miss, not a doubt',
        () async {
      final result = await checkWith([passed, passed]);
      expect(result.verdict, ProofVerdict.missed);
      expect(result.attempts, 1);
    });

    test('leaves out a test file it learned reacts to any edit', () async {
      Directory('${scratch.path}/test').createSync();
      for (final name in ['keep_test.dart', 'reads_source_test.dart']) {
        File('${scratch.path}/test/$name').writeAsStringSync('');
      }
      final calls = <List<String>>[];
      final runner = AuditRunner(
        scratchRoot: scratch.path,
        logger: logger,
        runTests: (tests) async {
          calls.add(tests);
          return passed;
        },
      )..learnedExclusions.add('test/reads_source_test.dart');
      await runner.check(
        const FileMutantFaults(file: 'lib/a.dart', tierOne: ['test/keep_test.dart'], tierTwo: ['test']),
        const _ChangesTheText(),
      );
      expect(calls.last, ['test/keep_test.dart']);
    });

    test('leaves the scratch source as it was', () async {
      await checkWith([caught]);
      expect(
        File('${scratch.path}/lib/session/session_state.dart').readAsStringSync(),
        'original',
      );
    });
  });

  group('the lines a change touched', () {
    const diff = 'diff --git a/lib/a.dart b/lib/a.dart\n'
        '--- a/lib/a.dart\n'
        '+++ b/lib/a.dart\n'
        '@@ -3,0 +4,2 @@ class A {\n'
        '+x\n'
        '+y\n'
        '@@ -10 +12 @@\n'
        '-old\n'
        '+new\n'
        '@@ -20,2 +21,0 @@\n'
        '-gone\n'
        '-gone\n'
        'diff --git a/lib/b.dart b/lib/b.dart\n'
        '--- a/lib/b.dart\n'
        '+++ b/lib/b.dart\n'
        '@@ -1,3 +1,3 @@\n';

    final changed = parseChangedLines(diff);

    test('an added block is a range of its new lines', () {
      expect(changed['lib/a.dart']!.first, (first: 4, last: 5));
    });

    test('a hunk with no count is one line', () {
      expect(changed['lib/a.dart']![1], (first: 12, last: 12));
    });

    test('lines only deleted leave no range', () {
      expect(changed['lib/a.dart'], hasLength(2));
    });

    test('each file has its own ranges', () {
      expect(changed['lib/b.dart'], [(first: 1, last: 3)]);
    });

    test('a line is changed when a range holds it', () {
      final ranges = changed['lib/a.dart']!;
      expect([isChanged(ranges, 4), isChanged(ranges, 5), isChanged(ranges, 6), isChanged(ranges, 12)],
          [true, true, false, true]);
    });
  });

  group('line mutants', () {
    List<String> idsOf(String line) =>
        [for (final (id, _) in mutantsOfLine(line, 1)) id];

    String? changed(String line, String id) =>
        mutantsOfLine(line, 1).firstWhere((m) => m.$1 == id).$2;

    test('an equality is flipped', () {
      expect(changed('  if (a == b) {', 'equals'), '  if (a != b) {');
    });

    test('a generic\'s angle bracket is never changed', () {
      expect(idsOf('  List<int> values = [];'), isNot(contains('lessThan')));
    });

    test('a comparison is changed to its neighbor', () {
      expect(changed('  if (a < b) {', 'lessThan'), '  if (a <= b) {');
    });

    test('nothing inside a string literal is changed', () {
      expect(idsOf("  final text = 'a == b && true';"), isEmpty);
    });

    test('nothing in a trailing comment is changed', () {
      expect(idsOf('  final x = a; // is a == b true'), isEmpty);
    });

    test('a number is raised by one', () {
      expect(changed('  final limit = 10;', 'number'), '  final limit = 11;');
    });

    test('a number inside an identifier is left alone', () {
      expect(idsOf('  final step2 = a;'), isEmpty);
    });

    test('a call statement can be removed', () {
      expect(idsOf('  notify(user);'), contains('deleteStatement'));
    });

    test('the tail of an expression body is never removed', () {
      expect(
        [for (final (id, _) in mutantsOfLine('      names.contains(feature);', 1, previous: '  bool has(String feature) =>')) id],
        isNot(contains('deleteStatement')),
      );
    });

    test('a call that starts a statement can be removed', () {
      expect(
        [for (final (id, _) in mutantsOfLine('  notify(user);', 1, previous: '  final a = 1;')) id],
        contains('deleteStatement'),
      );
    });

    test('a return is never removed', () {
      expect(idsOf('  return notify(user);'), isNot(contains('deleteStatement')));
    });

    test('a declaration is not a call statement', () {
      expect(idsOf('  final x = notify(user);'), isNot(contains('deleteStatement')));
    });

    test('an import is never changed', () {
      expect(idsOf("import 'package:a/a.dart';"), isEmpty);
    });

    test('a comment line is never changed', () {
      expect(idsOf('  // a == b'), isEmpty);
    });

    test('a negation is dropped', () {
      expect(changed('  if (!ready) {', 'negation'), '  if (ready) {');
    });

    test('a second match on a line is named apart from the first', () {
      expect(idsOf('  final ok = a == b && c == d;'), containsAll(['equals', 'equals#2']));
    });

    test('a mutant is described by its line and what changed', () {
      final root = Directory.systemTemp.createTempSync('mutant_desc_');
      File('${root.path}/a.dart').writeAsStringSync('int f() => 1;\nbool g(int a) => a == 2;\n');
      final faults = const FileMutantFaults(file: 'a.dart', tierOne: [], tierTwo: [])
          .faults(root.path);
      root.deleteSync(recursive: true);
      expect(faults.map((f) => f.description), contains(startsWith('line 2 equals:')));
    });
  });

  group('the tests a wider run is made of', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('proof_audit_expand_');
      for (final path in [
        'test/a/one_test.dart',
        'test/a/helper.dart',
        'test/b/deep/two_test.dart',
        'test/b/proof_audit_test.dart',
      ]) {
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync('');
      }
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('a directory is every test file under it', () {
      expect(
        expandTests(root.path, ['test/b'], const []),
        ['test/b/deep/two_test.dart', 'test/b/proof_audit_test.dart'],
      );
    });

    test('a file named twice is run once, and files that are not tests are left out', () {
      expect(
        expandTests(root.path, ['test/a/one_test.dart', 'test/a'], const []),
        ['test/a/one_test.dart'],
      );
    });

    test('an excluded test is left out of a directory it is in', () {
      expect(
        expandTests(root.path, ['test/b'], ['test/b/proof_audit_test.dart']),
        ['test/b/deep/two_test.dart'],
      );
    });

    test('the audit never runs its own tests as part of a wider run', () {
      expect(
        const TransitionTableFaults().excludedTests,
        contains('test/topology/proof_audit_test.dart'),
      );
    });
  });

  group('the report', () {
    Map<String, dynamic> row(
      String verdict, {
      int tier = 1,
      int attempts = 1,
      String fault = 'noHandoff x setup: suggestInvestigating -> unknown',
      List<String> caughtBy = const ['a proof'],
    }) =>
        {
          'proof': 'transitionTable',
          'fault': fault,
          'sourceFile': 'lib/session/session_state.dart',
          'sourceLine': 149,
          'verdict': verdict,
          'tier': tier,
          'attempts': attempts,
          'caughtBy': caughtBy,
        };

    test('counts a fault by its latest row', () {
      final text = renderReport([
        row('invalid', caughtBy: const []),
        row('caught', attempts: 2),
      ]);
      expect(text, contains('| caught by the named proofs (tier 1) | 1 |'));
      expect(text, contains('| invalid (did not compile or load): shows nothing | 0 |'));
    });

    test('leaves the control faults out of the counts', () {
      final control = {...row('missed', caughtBy: const []), 'proof': 'control'};
      final text = renderReport([control, row('caught')]);
      expect(text, contains('| total | 1 |'));
    });

    test('counts a fault only a generated-doc drift test caught', () {
      final text = renderReport([
        row('caught', caughtBy: const ['the checked-in doc docs/x.md matches the code']),
        row('caught', fault: 'noHandoff x setup: suggestInvestigating -> readyForDebug'),
      ]);
      expect(text, contains('regenerating the docs hides them | 1 |'));
    });

    test('counts the faults that were run again', () {
      final text = renderReport([row('caught', attempts: 2)]);
      expect(text, contains('repeated | 1 |'));
    });

    test('lists a missed fault with its file and line and says nothing caught it',
        () {
      final text = renderReport([row('missed', caughtBy: const [])]);
      expect(text, contains('`lib/session/session_state.dart:149` | nothing |'));
    });

    test('marks a cell a tier-2 test caught with a star', () {
      final text = renderReport([row('caught', tier: 2)]);
      expect(text, contains('0/1*'));
    });

    test('marks a cell nothing caught with a bang', () {
      final text = renderReport([row('missed', caughtBy: const [])]);
      expect(text, contains('0/1!'));
    });

    test('names the tests that carried the proof', () {
      final text = renderReport([row('caught', caughtBy: const ['the size pin'])]);
      expect(text, contains('| the size pin | 1 |'));
    });
  });

  group('every provider', () {
    for (final provider in auditProviders) {
      group(provider.proof, () {
        final all = provider.faults('.');

        test('has faults, and the same ones each time', () {
          expect(all, isNotEmpty);
          expect(
            provider.faults('.').map((f) => f.description).toList(),
            all.map((f) => f.description).toList(),
          );
        });

        test('describes each fault once', () {
          final descriptions = all.map((f) => f.description).toList();
          expect(descriptions.toSet(), hasLength(descriptions.length));
        });

        test('changes the source with every fault', () {
          for (final fault in all) {
            final original = File(fault.sourceFile).readAsStringSync();
            expect(fault.apply(original), isNot(original),
                reason: fault.description);
          }
        });

        test('stands for a line inside its file', () {
          for (final fault in all) {
            final length = File(fault.sourceFile).readAsLinesSync().length;
            expect(fault.sourceLine, inInclusiveRange(1, length),
                reason: fault.description);
          }
        });

        test('names tests that exist', () {
          for (final path in [...provider.tierOneTests, ...provider.tierTwoTests]) {
            expect(
              File(path).existsSync() || Directory(path).existsSync(),
              isTrue,
              reason: path,
            );
          }
        });
      });
    }

    test('the evidence matrix has 29 faults: five returns and two guards, and '
        'four arms each retargeted three ways', () {
      expect(const ClosureEvidenceFaults().faults('.'), hasLength(29));
    });

    test('the listener matrix has 45 faults: two reactions dropped from the '
        'debugComplete move, two lists given a second reaction, 14 events '
        'for the recorder, and 27 changes to the closer\'s permitted events', () {
      expect(const HandoffListenerFaults().faults('.'), hasLength(45));
    });

    test('the command matrix has 546 faults: for each of the 26 commands four '
        'flags, a wire name, two other entry sets and 14 events', () {
      expect(const ClaudartCommandFaults().faults('.'), hasLength(546));
    });
  });
}
