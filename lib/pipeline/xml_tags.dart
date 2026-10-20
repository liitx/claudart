
// xml_tags.dart — XML tag extraction utilities for agent output parsing.
//
// Pipeline steps output structured XML tags. These functions extract
// content between `<TAG>` and `</TAG>` by direct string scan — avoids
// the regex engine; the operation is `indexOf` + `substring`. Pure
// functions, no side effects.
//
// Three parsers:
//   tagOr               — case-sensitive; returns a fallback when absent.
//   tagOrNull           — case-sensitive; returns null when absent.
//   tagOrNullIgnoreCase — tag-name matched case-insensitively for
//                          LLM-emitted output that may not honor the
//                          system prompt's UPPER_SNAKE_CASE convention.
//
// The captured content is whitespace-trimmed but otherwise verbatim —
// the caller normalizes the value.
//
// Unicode safety: the case-insensitive path uses an ASCII-only fold
// (`A`..`Z` → `a`..`z`, everything else passes through unchanged) so
// the folded string preserves code-unit indices 1:1 with [text]. This
// matters because indices found in the folded haystack are reused to
// slice [text]; a length-changing fold (Dart's `toLowerCase()` can
// expand chars like Turkish `İ`) would corrupt the slice boundary.
//
// Wire tags the pipeline emits and parses are owned by [WireTag]. Its
// closing delimiter is composed from the tag name, so no source file has
// to spell a closing tag out literally.

const String _kDefaultFallback = '_Not determined._';
const int _kCodeUnitA = 0x41;
const int _kCodeUnitZ = 0x5A;
const int _kAsciiCaseBit = 0x20;

/// Tag names of the wire format, as consts so const prompt strings can
/// interpolate them. [WireTag] is built from these — one source of truth.
const String kChangesTagName = 'CHANGES';
const String kEditFileTagName = 'EDIT_FILE';

/// Wire tags exchanged with the implementer agent.
enum WireTag {
  changes(kChangesTagName),
  editFile(kEditFileTagName);

  const WireTag(this.tagName);

  final String tagName;

  /// Start of the opening delimiter, without attributes or `>`.
  String get openPrefix => '<$tagName';

  /// The closing delimiter.
  String get close => '</$tagName>';
}

/// Extracts the trimmed content between `<TAG>` and `</TAG>` in [text].
/// Returns [fallback] when the tag is absent. Case-sensitive.
String tagOr(String text, String tag, [String fallback = _kDefaultFallback]) =>
    _extractTag(text, tag, caseInsensitive: false) ?? fallback;

/// Case-sensitive [tagOr] variant that returns null when absent.
String? tagOrNull(String text, String tag) =>
    _extractTag(text, tag, caseInsensitive: false);

/// Case-insensitive variant. Use this for LLM-emitted output where
/// the tag name's case is unreliable. Tag names are matched via an
/// ASCII-only fold so non-ASCII content in [text] passes through
/// without shifting slice indices.
String? tagOrNullIgnoreCase(String text, String tag) =>
    _extractTag(text, tag, caseInsensitive: true);

/// Single tag-extraction primitive. Scans [text] for `<tag>...</tag>`
/// via [String.indexOf]. When [caseInsensitive] is true, both
/// haystack and needles are ASCII-folded so indices stay 1:1 with
/// [text] (see header comment for the Unicode-safety rationale).
String? _extractTag(String text, String tag, {required bool caseInsensitive}) {
  final haystack = caseInsensitive ? _asciiLowerFold(text) : text;
  final openTag = caseInsensitive ? _asciiLowerFold(tag) : tag;
  final openNeedle = '<$openTag>';
  final closeNeedle = '</$openTag>';

  final openIndex = haystack.indexOf(openNeedle);
  if (openIndex < 0) return null;

  final contentStart = openIndex + openNeedle.length;
  final closeIndex = haystack.indexOf(closeNeedle, contentStart);
  if (closeIndex < 0) return null;

  return text.substring(contentStart, closeIndex).trim();
}

/// ASCII-only lower-case fold. Each code unit in [s] is mapped:
/// `'A'`..`'Z'` → `'a'`..`'z'` by setting the case bit; every other
/// code unit (including non-ASCII chars and existing lower-case
/// letters) passes through unchanged.
///
/// Unlike [String.toLowerCase] this is length-preserving — the result
/// has the same number of code units as [s], so an `indexOf` hit in
/// the fold corresponds to the same index in [s].
String _asciiLowerFold(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    out.writeCharCode(
      (c >= _kCodeUnitA && c <= _kCodeUnitZ) ? c | _kAsciiCaseBit : c,
    );
  }
  return out.toString();
}