// table_faults.dart — every single-cell change to the handoff transition table
//
// The table is `HandoffStatus.after`: for each (status, event) the status the
// move lands on, or null when the move is rejected. A fault changes exactly one
// cell to another value (null, or any other status), so for 8 statuses and 14
// events there are 112 cells and 8 faults for each. The faulty source replaces
// `after` with a lookup in a generated table, so the change is exact whatever
// the grouping of arms in the real switch. Each cell is tied to the line where
// the real switch decides it, so a missed fault points at that line.

import 'dart:io';

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/session_state.dart';

import 'fault.dart';

const _sourceFilePath = 'lib/session/session_state.dart';
const _methodSignature =
    '  HandoffStatus? after(HandoffEvent event) => switch (event) {';
const _methodEnd = '      };';
const _tableName = '_auditedCells';

/// How a fault's description is written, and read back by the report.
final cellFaultPattern = RegExp(r'^(\w+) x (\w+): (\w+) -> (\w+)$');

String _name(HandoffStatus? status) => status?.name ?? 'null';

String _literal(HandoffStatus? status) =>
    status == null ? 'null' : 'HandoffStatus.${status.name}';

/// One cell of the table changed to [replacement].
class TableCellFault extends SeededFault {
  const TableCellFault({
    required this.status,
    required this.event,
    required this.current,
    required this.replacement,
    required this.sourceLine,
    required this.cells,
  });

  final HandoffStatus status;
  final HandoffEvent event;
  final HandoffStatus? current;
  final HandoffStatus? replacement;

  /// Every cell of the unchanged table.
  final Map<(HandoffStatus, HandoffEvent), HandoffStatus?> cells;

  @override
  final int sourceLine;

  @override
  String get proof => 'transitionTable';

  @override
  String get sourceFile => _sourceFilePath;

  @override
  String get description =>
      '${status.name} x ${event.name}: ${_name(current)} -> ${_name(replacement)}';

  @override
  String apply(String source) {
    final lines = source.split('\n');
    final start = lines.indexOf(_methodSignature);
    if (start < 0) throw StateError('the after signature is not in $_sourceFilePath');
    final end = lines.indexOf(_methodEnd, start);
    if (end < 0) throw StateError('the end of after is not in $_sourceFilePath');
    final entries = [
      for (final entry in cells.entries)
        '  (HandoffStatus.${entry.key.$1.name}, HandoffEvent.${entry.key.$2.name}): '
            '${_literal(entry.key == (status, event) ? replacement : entry.value)},',
    ];
    return [
      ...lines.sublist(0, start),
      '  HandoffStatus? after(HandoffEvent event) => $_tableName[(this, event)];',
      ...lines.sublist(end + 1),
      '',
      'const $_tableName = <(HandoffStatus, HandoffEvent), HandoffStatus?>{',
      ...entries,
      '};',
      '',
    ].join('\n');
  }
}

/// The transition table's faults, against the proofs and matrices that check it.
class TransitionTableFaults extends FaultProvider {
  const TransitionTableFaults();

  @override
  String get proof => 'transitionTable';

  @override
  List<String> get tierOneTests => const [
        'test/topology/transition_proofs_test.dart',
        'test/topology/transition_matrix_test.dart',
        'test/topology/transition_expectation_test.dart',
        'test/topology/handoff_topology_test.dart',
        'test/session/session_state_test.dart',
      ];

  @override
  List<String> get tierTwoTests => const [
        'test/topology',
        'test/session',
        'test/conformance',
        'test/matrix',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$_sourceFilePath').readAsLinesSync();
    final lineOf = _cellLines(lines);
    final cells = {
      for (final event in HandoffEvent.values)
        for (final status in HandoffStatus.values)
          (status, event): status.after(event),
    };
    return [
      for (final event in HandoffEvent.values)
        for (final status in HandoffStatus.values)
          for (final replacement in <HandoffStatus?>[null, ...HandoffStatus.values])
            if (replacement != cells[(status, event)])
              TableCellFault(
                status: status,
                event: event,
                current: cells[(status, event)],
                replacement: replacement,
                sourceLine: lineOf[(status, event)]!,
                cells: cells,
              ),
    ];
  }
}

/// The line of the real switch that decides each cell. Fails unless every
/// cell is found exactly once, so the mapping is itself total.
Map<(HandoffStatus, HandoffEvent), int> _cellLines(List<String> lines) {
  final start = lines.indexOf(_methodSignature);
  final end = lines.indexOf(_methodEnd, start);
  final statusNames = {for (final status in HandoffStatus.values) status.name};
  final eventHeader =
      RegExp(r'^\s*((?:HandoffEvent\.\w+\s*(?:\|\|\s*)?)+)=> switch \(this\) \{');
  final eventName = RegExp(r'HandoffEvent\.(\w+)');
  final arm = RegExp(r'^\s*(\w+)\s*(\|\||=>)');
  final found = <(HandoffStatus, HandoffEvent), int>{};
  var events = <HandoffEvent>[];
  for (var index = start + 1; index < end; index++) {
    final header = eventHeader.firstMatch(lines[index]);
    if (header != null) {
      events = [
        for (final name in eventName.allMatches(header.group(1)!))
          HandoffEvent.values.byName(name.group(1)!),
      ];
      continue;
    }
    final match = arm.firstMatch(lines[index]);
    if (events.isEmpty || match == null || !statusNames.contains(match.group(1))) {
      continue;
    }
    final status = HandoffStatus.values.byName(match.group(1)!);
    for (final event in events) {
      final key = (status, event);
      if (found.containsKey(key)) {
        throw StateError('cell $key is decided twice in $_sourceFilePath');
      }
      found[key] = index + 1;
    }
  }
  final expected = HandoffStatus.values.length * HandoffEvent.values.length;
  if (found.length != expected) {
    throw StateError('found ${found.length} of $expected cells in $_sourceFilePath');
  }
  return found;
}
