import 'package:claudart/workspace/project_sensitivity.dart';
import 'package:test/test.dart';

void main() {
  group('reconcileSensitivity: a disagreement never weakens', () {
    // Independent literals: (chosen at link, owner marked) -> recorded.
    const table = {
      (false, false): false,
      (true, false): true,
      (false, true): true,
      (true, true): true,
    };
    table.forEach((inputs, expected) {
      test('chosen=${inputs.$1}, owner marked=${inputs.$2} -> $expected', () {
        expect(
          reconcileSensitivity(
            chosen: inputs.$1,
            ownerMarkedSensitive: inputs.$2,
          ),
          expected,
        );
      });
    });
  });
}
