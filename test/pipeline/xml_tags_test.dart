// xml_tags_test.dart — tagOr / tagOrNull / tagOrNullIgnoreCase.
//
// Three parsers, three cases: case-sensitive match, no match, and the
// case-insensitive variant introduced for LLM-emitted tags.

import 'package:claudart/pipeline/xml_tags.dart';
import 'package:test/test.dart';

void main() {
  group('tagOr', () {
    test('returns content when tag present', () {
      expect(tagOr('<X>hello</X>', 'X'), equals('hello'));
    });

    test('returns fallback when tag absent', () {
      expect(
        tagOr('no tags here', 'X', 'FALLBACK'),
        equals('FALLBACK'),
      );
    });

    test('default fallback when none provided', () {
      expect(tagOr('no tags', 'X'), isNotEmpty);
    });

    test('case-sensitive — lower-case tag in input misses upper-case lookup',
        () {
      expect(tagOr('<x>hello</x>', 'X', 'MISS'), equals('MISS'));
    });
  });

  group('tagOrNull', () {
    test('returns content when tag present', () {
      expect(tagOrNull('<X>hello</X>', 'X'), equals('hello'));
    });

    test('returns null when tag absent', () {
      expect(tagOrNull('no tags', 'X'), isNull);
    });

    test('case-sensitive — lower-case tag returns null on upper lookup', () {
      expect(tagOrNull('<x>hello</x>', 'X'), isNull);
    });

    test('content with newlines + leading/trailing whitespace is trimmed',
        () {
      expect(
        tagOrNull('<X>\n  hello\n  </X>', 'X'),
        equals('hello'),
      );
    });
  });

  group('tagOrNullIgnoreCase', () {
    test('upper-case tag matches upper-case lookup', () {
      expect(
        tagOrNullIgnoreCase('<CATEGORY>feature</CATEGORY>', 'CATEGORY'),
        equals('feature'),
      );
    });

    test('lower-case tag matches upper-case lookup', () {
      expect(
        tagOrNullIgnoreCase('<category>feature</category>', 'CATEGORY'),
        equals('feature'),
      );
    });

    test('mixed-case tag matches', () {
      expect(
        tagOrNullIgnoreCase('<Category>feature</Category>', 'CATEGORY'),
        equals('feature'),
      );
    });

    test('mismatched open/close case still matches', () {
      // Both delimiters are folded independently — `<CATEGORY>...</category>`
      // matches because the haystack is folded once before searching for
      // each needle. Documents the tolerance level.
      expect(
        tagOrNullIgnoreCase('<CATEGORY>feature</category>', 'CATEGORY'),
        equals('feature'),
      );
    });

    test('returns null when tag absent', () {
      expect(tagOrNullIgnoreCase('no tags', 'CATEGORY'), isNull);
    });

    test('value content preserved verbatim (not lowered)', () {
      expect(
        tagOrNullIgnoreCase('<x>HelloWorld</x>', 'X'),
        equals('HelloWorld'),
      );
    });
  });

  // ── Unicode safety — ASCII-only fold preserves slice indices ─────────────
  //
  // Dart's `String.toLowerCase()` can change code-unit length on certain
  // chars (Turkish dotless İ → i̇). The implementation uses an ASCII-only
  // fold so non-ASCII content in the haystack passes through unchanged
  // and slice boundaries stay aligned. These rows cover the failure modes
  // a naive `toLowerCase()` implementation would hit.

  group('tagOrNullIgnoreCase preserves slice indices through non-ASCII', () {
    test('non-ASCII inside tag content is preserved verbatim', () {
      const content = 'résumé — café';
      const raw = '<NOTE>$content</NOTE>';
      expect(tagOrNullIgnoreCase(raw, 'NOTE'), equals(content));
    });

    test('Turkish dotted I in surrounding prose does not shift indices', () {
      // Turkish İ would expand under default toLowerCase. Keeping it in
      // prose around the tag and confirming the extracted value is
      // exactly what's between the delimiters proves the fold is
      // length-preserving.
      const content = 'value';
      const raw = 'note İstanbul <T>$content</T> trailing İ';
      expect(tagOrNullIgnoreCase(raw, 'T'), equals(content));
    });

    test('surrogate pair in tag content is preserved', () {
      // Emoji are surrogate pairs — two code units per character.
      const content = 'fire 🔥 hot';
      const raw = '<X>$content</X>';
      expect(tagOrNullIgnoreCase(raw, 'X'), equals(content));
    });
  });

  // ── Empty-content semantics ───────────────────────────────────────────────

  group('whitespace-only content trims to empty string', () {
    test('tagOrNull returns empty string when content is only whitespace', () {
      // Documents the contract: trim() is applied; result may be ''.
      // Callers that want null-for-empty must normalize themselves
      // (see CategorizeTag.extractFrom).
      expect(tagOrNull('<X>   \n  </X>', 'X'), equals(''));
    });
  });

  // ── Wire tags ─────────────────────────────────────────────────────────────

  group('WireTag delimiters are built from the tag name', () {
    for (final tag in WireTag.values) {
      test(tag.name, () {
        expect(tag.openPrefix, equals('<${tag.tagName}'));
        expect(tag.close, equals('</${tag.tagName}>'));
      });
    }
  });

  // ── ASCII fold range ──────────────────────────────────────────────────────

  // The fold maps only 'A'..'Z'. '@' (0x40) sits just below that range and '['
  // (0x5B) just above it; setting the case bit on either would make it equal
  // '`' (0x60) or '{' (0x7B), so a tag of one must not match text of the other.
  group('tagOrNullIgnoreCase folds exactly A to Z', () {
    test('Z folds to z', () {
      expect(tagOrNullIgnoreCase('<z>x</z>', 'Z'), equals('x'));
    });

    test('@ below A is not folded', () {
      expect(tagOrNullIgnoreCase('<`>x</`>', '@'), isNull);
    });

    test('[ above Z is not folded', () {
      expect(tagOrNullIgnoreCase('<{>x</{>', '['), isNull);
    });
  });
}
