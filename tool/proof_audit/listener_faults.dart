// listener_faults.dart — single changes to which reactions a status change calls for
//
// `listenersFor` names the reactions each move calls for and
// `HandoffListenerKind.mayEmit` names the events a reaction may return for the
// writer to apply. Together they decide whether a verified fix closes its own
// session, so each fact is changed on its own: a reaction dropped from or added
// to a move, and an event added to, removed from or swapped in a reaction's
// permitted events.

import 'dart:io';

import 'package:claudart/session/handoff_event.dart';

import 'fault.dart';
import 'line_faults.dart';

const _sourceFilePath = 'lib/session/handoff_listeners.dart';
const _record = 'HandoffListenerKind.recordTransition';
const _teardown = 'HandoffListenerKind.teardownWhenConverged';
const _recordKind = '  recordTransition(mayEmit: {}),';
const _teardownKind =
    '  teardownWhenConverged(mayEmit: {HandoffEvent.tornDown});';
const _singleRecordList = 'const [$_record],';

class HandoffListenerFaults extends FaultProvider {
  const HandoffListenerFaults();

  @override
  String get proof => 'handoffListeners';

  @override
  List<String> get coveredTables => const ['listenersFor'];

  @override
  List<String> get tierOneTests => const [
        'test/session/handoff_listeners_test.dart',
        'test/session/handoff_store_test.dart',
        'test/session/transition_bus_test.dart',
      ];

  @override
  List<String> get tierTwoTests => const [
        'test/session',
        'test/commands',
        'test/topology',
        'test/conformance',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$_sourceFilePath').readAsStringSync().split('\n');
    final faults = <SeededFault>[];

    LineEditFault edit(int number, String description, List<String> Function(List<String>) change) =>
        LineEditFault(
          proof: proof,
          description: description,
          sourceFile: _sourceFilePath,
          sourceLine: number,
          edit: change,
        );

    int lineOf(String text) {
      final index = lines.indexWhere((l) => l.contains(text));
      if (index < 0) throw StateError('"$text" is not in $_sourceFilePath');
      return index + 1;
    }

    // The reactions a move calls for.
    for (final listed in [_record, _teardown]) {
      final number = lines.indexWhere((l) => l.trim() == '$listed,') + 1;
      if (number == 0) throw StateError('$listed is not listed in $_sourceFilePath');
      faults.add(edit(
        number,
        'listenersFor: the debugComplete move no longer calls for '
        '${listed.split('.').last}',
        (all) => [...all.sublist(0, number - 1), ...all.sublist(number)],
      ));
    }
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim() != _singleRecordList) continue;
      final number = index + 1;
      faults.add(edit(
        number,
        'listenersFor: the moves on line $number also call for teardownWhenConverged',
        (all) => replacingLine(
          all,
          number,
          lines[index].replaceFirst(_singleRecordList, 'const [$_record, $_teardown],'),
        ),
      ));
    }

    // The events a reaction may return.
    for (final event in HandoffEvent.values) {
      final number = lineOf(_recordKind);
      faults.add(edit(
        number,
        'recordTransition may emit ${event.name}',
        (all) => replacingLine(
          all,
          number,
          '  recordTransition(mayEmit: {HandoffEvent.${event.name}}),',
        ),
      ));
    }
    final teardownNumber = lineOf(_teardownKind);
    faults.add(edit(
      teardownNumber,
      'teardownWhenConverged may emit nothing',
      (all) => replacingLine(
        all,
        teardownNumber,
        '  teardownWhenConverged(mayEmit: {});',
      ),
    ));
    for (final event in HandoffEvent.values) {
      if (event == HandoffEvent.tornDown) continue;
      faults.add(edit(
        teardownNumber,
        'teardownWhenConverged may emit ${event.name} instead of tornDown',
        (all) => replacingLine(
          all,
          teardownNumber,
          '  teardownWhenConverged(mayEmit: {HandoffEvent.${event.name}});',
        ),
      ));
      faults.add(edit(
        teardownNumber,
        'teardownWhenConverged may also emit ${event.name}',
        (all) => replacingLine(
          all,
          teardownNumber,
          '  teardownWhenConverged(mayEmit: {HandoffEvent.tornDown, HandoffEvent.${event.name}});',
        ),
      ));
    }
    return faults;
  }
}
