// transition_proofs_test.dart — properties of the handoff state machine, proved
// by exhaustive computation over its finite sets.
//
// The machine is the triple (S, E, delta): S = HandoffStatus (8 statuses),
// E = HandoffEvent (14 events), and delta : S x E -> S u {rejected}, the
// partial function HandoffStatus.after (null is "rejected"). Every property
// below is a statement about that finite object, so it is decided by checking
// all |S| * |E| = 112 cells or by a graph search over the legal ones; none is a
// sample. The expected values are independent literals, so a change to the table
// that alters a property fails here until the change is made on purpose.
//
// Not proved here, and said so: termination of listener chains (there are no
// listeners yet), and anything about what a command does besides the move.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/knowledge_transfer.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

const _fixturePath = 'test/fixtures/real_transitions.jsonl';

/// Independent literals.
const _legalCellCount = 37;
const _statusCount = 8;
const _eventCount = 14;
const _selfLoops = {
  HandoffStatus.suggestInvestigating,
  HandoffStatus.readyForDebug,
  HandoffStatus.debugInProgress,
};

/// The legal moves of the machine as edges, status -> statuses.
Map<HandoffStatus, Set<HandoffStatus>> _edges() => {
      for (final from in HandoffStatus.values)
        from: {
          for (final event in HandoffEvent.values)
            if (from.after(event) != null) from.after(event)!,
        },
    };

/// Every status reachable from [start] over legal moves, [start] excluded
/// unless a cycle returns to it.
Set<HandoffStatus> _reachableFrom(HandoffStatus start) {
  final edges = _edges();
  final seen = <HandoffStatus>{};
  final frontier = [start];
  while (frontier.isNotEmpty) {
    for (final next in edges[frontier.removeLast()]!) {
      if (seen.add(next)) frontier.add(next);
    }
  }
  return seen;
}

void main() {
  final live = HandoffStatus.values.where((s) => s != HandoffStatus.unknown);

  group('delta is a total, single-valued partial function', () {
    test('|S| and |E| are as declared', () {
      expect(HandoffStatus.values.length, _statusCount);
      expect(HandoffEvent.values.length, _eventCount);
    });

    // One test per cell: each of the |S| x |E| cells is decided (delta returns
    // a status or null, never throws) and decided the same way twice.
    for (final from in HandoffStatus.values) {
      for (final event in HandoffEvent.values) {
        test('${from.name} --${event.name}--> is decided and deterministic',
            () {
          expect(from.after(event), from.after(event));
        });
      }
    }

    test('exactly $_legalCellCount cells are legal', () {
      final legal = [
        for (final from in HandoffStatus.values)
          for (final event in HandoffEvent.values)
            if (from.after(event) != null) (from, event),
      ];
      expect(legal.length, _legalCellCount);
    });
  });

  group('the shape of the graph over legal moves', () {
    test('unknown has no move out and no move in', () {
      expect(_edges()[HandoffStatus.unknown], isEmpty);
      for (final from in live) {
        expect(
          _edges()[from]!.contains(HandoffStatus.unknown),
          isFalse,
          reason: '${from.name} must not move to unknown',
        );
      }
    });

    test('every live status is reachable from noHandoff', () {
      expect(
        _reachableFrom(HandoffStatus.noHandoff).union({HandoffStatus.noHandoff}),
        live.toSet(),
      );
    });

    test('no live status is a trap: each can reach noHandoff', () {
      for (final from in live) {
        if (from == HandoffStatus.noHandoff) continue;
        expect(
          _reachableFrom(from).contains(HandoffStatus.noHandoff),
          isTrue,
          reason: '${from.name} has no way back to noHandoff',
        );
      }
    });

    test('the live statuses form one strongly connected component', () {
      for (final from in live) {
        expect(
          _reachableFrom(from).union({from}),
          live.toSet(),
          reason: '${from.name} cannot reach every live status',
        );
      }
    });

    test('exactly the statuses a session may repeat in have a self-loop', () {
      expect(
        {
          for (final status in HandoffStatus.values)
            if (_edges()[status]!.contains(status)) status,
        },
        _selfLoops,
      );
    });
  });

  group('P14: tornDown is legal exactly where the transfer is complete', () {
    for (final status in HandoffStatus.values) {
      final expectsConverged = status.knowledgeTransferExpectation ==
          KnowledgeTransferExpectation.converged;
      test('${status.name}: tornDown is legal ${expectsConverged ? '' : 'not'}',
          () {
        expect(status.after(HandoffEvent.tornDown) != null, expectsConverged);
      });
    }
  });

  group('the real moves replay through delta', () {
    final moves = [
      for (final line in File(_fixturePath).readAsLinesSync())
        if (line.isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ];

    test('the fixture holds the 44 moves read from the real log', () {
      expect(moves.length, 44);
    });

    test('every real move is legal and lands where it was logged', () {
      for (final move in moves) {
        final from = HandoffStatus.values.byName(move['from'] as String);
        final event = HandoffEvent.values.byName(move['event'] as String);
        expect(
          from.after(event)?.name,
          move['to'],
          reason: '${move['command']}: ${from.name} --${event.name}-->',
        );
      }
    });
  });
}
