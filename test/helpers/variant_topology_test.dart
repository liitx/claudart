import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import 'variant_topology.dart';

enum _Light {
  red(stops: true, seconds: 30),
  green(stops: false, seconds: 25);

  const _Light({required this.stops, required this.seconds});
  final bool stops;
  final int seconds;
}

void main() {
  group('topologyOf', () {
    test('maps each variant to its own getter value, in declaration order', () {
      final topology = topologyOf(_Light.values, (l) => l.stops);
      expect(topology, {_Light.red: true, _Light.green: false});
      expect(topology.keys.toList(), _Light.values);
    });

    test('works for any getter type', () {
      expect(
        topologyOf(_Light.values, (l) => l.seconds),
        {_Light.red: 30, _Light.green: 25},
      );
    });
  });

  group('renderTopology', () {
    test('renders one row per variant, one column per named getter, exactly',
        () {
      expect(
        renderTopology<_Light>(
          _Light.values,
          {'stops': (l) => l.stops, 'seconds': (l) => l.seconds},
        ),
        '| variant | stops | seconds |\n'
        '|---|---|---|\n'
        '| red | true | 30 |\n'
        '| green | false | 25 |',
      );
    });

    test('a real enum: one row per HandoffStatus variant', () {
      final table = renderTopology<HandoffStatus>(HandoffStatus.values, {
        'value': (s) => s.value,
        'canStartDebug': (s) => s.canStartDebug,
        'isPersisted': (s) => s.isPersisted,
      });
      // header + divider + one row per variant
      expect(table.split('\n'), hasLength(2 + HandoffStatus.values.length));
    });
  });
}
