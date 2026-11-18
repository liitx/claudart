// debug_disposition_test.dart — whether debug has been, will be, or need not be
// run for a handoff, as the handoff records it.

import 'package:claudart/session/debug_disposition.dart';
import 'package:test/test.dart';

/// Independent literals: how each disposition is written in a handoff.
const _wire = <DebugDisposition, String>{
  DebugDisposition.pending: 'pending',
  DebugDisposition.done: 'done',
  DebugDisposition.verified: 'verified',
  DebugDisposition.notApplicable: 'not-applicable',
  DebugDisposition.skipped: 'skipped',
};

/// Independent literals: whether the handoff is resolved as far as debug goes.
const _resolved = <DebugDisposition, bool>{
  DebugDisposition.pending: false,
  DebugDisposition.done: true,
  DebugDisposition.verified: true,
  DebugDisposition.notApplicable: true,
  DebugDisposition.skipped: true,
};

void main() {
  group('$DebugDisposition.wire', () {
    test('every disposition has a pinned spelling', () {
      expect(_wire.keys.toSet(), DebugDisposition.values.toSet());
    });

    for (final disposition in DebugDisposition.values) {
      test('${disposition.name}: ${_wire[disposition]}', () {
        expect(disposition.wire, _wire[disposition]);
      });

      test('${disposition.name}: round-trips through fromWire', () {
        expect(DebugDisposition.fromWire(disposition.wire), disposition);
      });
    }

    test('no two dispositions share a spelling', () {
      expect(
        DebugDisposition.values.map((d) => d.wire).toSet().length,
        DebugDisposition.values.length,
      );
    });
  });

  group('$DebugDisposition.fromWire', () {
    test('an unknown spelling is null, not a guess', () {
      expect(DebugDisposition.fromWire('maybe'), isNull);
    });

    test('a placeholder is null', () {
      expect(DebugDisposition.fromWire('_Not yet determined._'), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(DebugDisposition.fromWire('  done \n'), DebugDisposition.done);
    });
  });

  group('$DebugDisposition.isResolved', () {
    test('every disposition has a pinned answer', () {
      expect(_resolved.keys.toSet(), DebugDisposition.values.toSet());
    });

    for (final disposition in DebugDisposition.values) {
      test('${disposition.name}: ${_resolved[disposition]}', () {
        expect(disposition.isResolved, _resolved[disposition]);
      });
    }
  });
}
