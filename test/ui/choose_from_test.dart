// choose_from_test.dart — turning a menu pick back into the choice it names.

import 'package:claudart/ui/menu.dart';
import 'package:test/test.dart';

enum _Pick { first, second, third }

void main() {
  group('chooseFrom', () {
    for (final choice in _Pick.values) {
      test('picking index ${choice.index} chooses ${choice.name}', () {
        expect(
          chooseFrom(_Pick.values, (c) => c.name, (items) => choice.index),
          choice,
        );
      });
    }

    test('shows one label per choice, in order', () {
      List<String>? shown;
      chooseFrom(_Pick.values, (c) => 'label ${c.name}', (items) {
        shown = items;
        return 0;
      });
      expect(shown, ['label first', 'label second', 'label third']);
    });

    test('a pick that names no choice is a range error, not a guess', () {
      expect(
        () => chooseFrom(_Pick.values, (c) => c.name, (items) => 3),
        throwsRangeError,
      );
    });
  });
}
