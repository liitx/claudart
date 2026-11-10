// The proof audit's own checks: its faults are the whole table, its reading of
// a test run is right, and a fault it builds is the one change it says it is.
// An audit that cannot be trusted would only move the doubt.

import 'dart:io';

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../../tool/proof_audit/runner.dart';
import '../../tool/proof_audit/table_faults.dart';

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

    test('lines that are not JSON events are ignored', () {
      expect(judgeTestRun('not json\n{broken\n', 0).failed, isEmpty);
    });
  });
}
