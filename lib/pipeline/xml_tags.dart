// xml_tags.dart — XML tag extraction utilities for agent output parsing
//
// Pipeline steps output structured XML tags. These functions extract content
// from those tags. Both are pure functions — no side effects.
//
// Convention: tags are UPPER_SNAKE_CASE (ROOT_CAUSE, SCOPE_FILES, CHANGES, etc.)

/// Extracts content between `<TAG>` and `</TAG>`.
/// Returns a fallback string when the tag is absent.
///
/// ∀ text, tag: tagOr(text, tag, fb) == fb ↔ tag ∉ text
String tagOr(String text, String tag, [String fallback = '_Not determined._']) {
  final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(text);
  return match?.group(1)?.trim() ?? fallback;
}

/// Extracts content between `<TAG>` and `</TAG>`.
/// Returns null when the tag is absent.
///
/// ∀ text, tag: tagOrNull(text, tag) == null ↔ tag ∉ text
String? tagOrNull(String text, String tag) {
  final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(text);
  return match?.group(1)?.trim();
}
