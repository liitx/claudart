// handoff_section.dart — one section of a handoff, as a value.
//
// A handoff section is real content or a placeholder. Holding it as a plain
// String made every reader repeat the same blank check on a bare string; a
// section knows whether it has content, and a field typed as one cannot be
// handed a stray string by mistake.

import 'handoff_placeholder.dart';

/// The text of one handoff section.
final class HandoffSection {
  const HandoffSection(this.text);

  /// The section as written in the handoff, placeholder included.
  final String text;

  /// Whether the section holds no real content.
  bool get isBlank => HandoffPlaceholder.isBlank(text);

  /// The text when there is content, else null.
  String? get contentOrNull => isBlank ? null : text;

  @override
  bool operator ==(Object other) =>
      other is HandoffSection && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => text;
}
