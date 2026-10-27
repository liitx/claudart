// check_duplicate_literals_test.dart — which string literals a file repeats,
// and the ratchet that stops the number growing.
//
// The tool prints a nudge after every edit; this makes the same finding a gate.
// The count of repeated literals across lib/ may only go down: extracting a
// repeat to a named constant or enum getter lowers it, adding one fails here.

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/check_duplicate_literals.dart';

/// Repeated literals found across lib/ today, counted once per file. A ratchet:
/// lower it as repeats are extracted; it must never be raised.
const _knownRepeatedLiterals = 175;

void main() {
  group('repeatedLiterals', () {
    test('finds a literal written twice', () {
      expect(
        repeatedLiterals(["var a = 'same text';", "var b = 'same text';"]),
        ['same text'],
      );
    });

    test('finds nothing when every literal is distinct', () {
      expect(repeatedLiterals(["var a = 'one';", "var b = 'two';"]), isEmpty);
    });

    test('ignores import lines', () {
      expect(
        repeatedLiterals(["import 'a/b.dart';", "import 'a/b.dart';"]),
        isEmpty,
      );
    });

    test('counts single and double quotes as the same literal', () {
      expect(
        repeatedLiterals(["var a = 'dup';", 'var b = "dup";']),
        ['dup'],
      );
    });

    test('ignores a literal shorter than three characters', () {
      expect(repeatedLiterals(["var a = 'ab';", "var b = 'ab';"]), isEmpty);
    });
  });

  group('the ratchet', () {
    test('repeated literals in lib/ do not grow', () {
      var total = 0;
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          total += repeatedLiterals(entity.readAsLinesSync()).length;
        }
      }
      expect(
        total,
        lessThanOrEqualTo(_knownRepeatedLiterals),
        reason: 'a string literal is repeated in lib/: extract it to a named '
            'constant or an enum getter, then lower _knownRepeatedLiterals',
      );
    });
  });
}
