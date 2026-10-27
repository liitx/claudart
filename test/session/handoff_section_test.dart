// handoff_section_test.dart — one section of a handoff, as a value that knows
// whether it holds real content.

import 'package:claudart/session/handoff_placeholder.dart';
import 'package:claudart/session/handoff_section.dart';
import 'package:test/test.dart';

void main() {
  group('$HandoffSection.isBlank', () {
    for (final placeholder in HandoffPlaceholder.values) {
      test('${placeholder.name} is blank', () {
        expect(HandoffSection(placeholder.text).isBlank, isTrue);
      });
    }

    test('an empty section is blank', () {
      expect(const HandoffSection('').isBlank, isTrue);
    });

    test('real content is not blank', () {
      expect(const HandoffSection('Off-by-one in foo()').isBlank, isFalse);
    });
  });

  group('$HandoffSection.contentOrNull', () {
    test('is the text when there is content', () {
      expect(const HandoffSection('a cause').contentOrNull, 'a cause');
    });

    test('is null for a placeholder', () {
      expect(
        HandoffSection(HandoffPlaceholder.nothingYet.text).contentOrNull,
        isNull,
      );
    });
  });

  group('$HandoffSection value', () {
    test('two sections with the same text are equal', () {
      expect(const HandoffSection('x'), const HandoffSection('x'));
      expect(const HandoffSection('x').hashCode, const HandoffSection('x').hashCode);
    });

    test('sections with different text are not equal', () {
      expect(const HandoffSection('x'), isNot(const HandoffSection('y')));
    });

    test('prints as its text', () {
      expect('${const HandoffSection('cause')}', 'cause');
    });
  });
}
