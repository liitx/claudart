// The proof audit's own checks: its faults are the whole table, its reading of
// a test run is right, and a fault it builds is the one change it says it is.
// An audit that cannot be trusted would only move the doubt.

import 'dart:io';

import 'package:claudart/io/file_io.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../../tool/proof_audit/closure_faults.dart';
import '../../tool/proof_audit/command_faults.dart';
import '../../tool/proof_audit/fault.dart';
import '../../tool/proof_audit/listener_faults.dart';
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

    test('leaves the scratch source as it was', () async {
      await checkWith([caught]);
      expect(
        File('${scratch.path}/lib/session/session_state.dart').readAsStringSync(),
        'original',
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
    const providers = <FaultProvider>[
      TransitionTableFaults(),
      ClosureEvidenceFaults(),
      ClaudartCommandFaults(),
      HandoffListenerFaults(),
    ];

    for (final provider in providers) {
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
