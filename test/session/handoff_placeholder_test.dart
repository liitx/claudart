// handoff_placeholder_test.dart — the text a handoff section holds before
// anything real is written to it, and the one rule for telling it from content.

import 'package:claudart/session/handoff_placeholder.dart';
import 'package:test/test.dart';

/// Independent literals: what each placeholder is spelled as in a handoff.
const _spelling = <HandoffPlaceholder, String>{
  HandoffPlaceholder.notYetDetermined: '_Not yet determined._',
  HandoffPlaceholder.nothingYet: '_Nothing yet._',
};

void main() {
  group('$HandoffPlaceholder', () {
    test('every variant has a pinned spelling', () {
      expect(_spelling.keys.toSet(), HandoffPlaceholder.values.toSet());
    });

    for (final placeholder in HandoffPlaceholder.values) {
      test('${placeholder.name}: starts with the blank marker', () {
        expect(placeholder.text, startsWith(HandoffPlaceholder.blankMarker));
      });

      test('${placeholder.name}: text is its pinned spelling', () {
        expect(placeholder.text, _spelling[placeholder]);
      });

      test('${placeholder.name}: is blank', () {
        expect(HandoffPlaceholder.isBlank(placeholder.text), isTrue);
      });
    }
  });

  group('$HandoffPlaceholder.isBlank', () {
    test('an empty section is blank', () {
      expect(HandoffPlaceholder.isBlank(''), isTrue);
    });

    test('the spelling older handoffs hold is still blank', () {
      expect(HandoffPlaceholder.isBlank('_Not determined._'), isTrue);
    });

    test('real content is not blank', () {
      expect(HandoffPlaceholder.isBlank('Off-by-one in foo()'), isFalse);
    });

    test('content that merely mentions a placeholder is not blank', () {
      expect(HandoffPlaceholder.isBlank('see _Not yet determined._'), isFalse);
    });
  });
}
