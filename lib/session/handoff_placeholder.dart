// handoff_placeholder.dart — what a handoff section says before anything real
// is written to it.
//
// One spelling per placeholder, and one rule for telling a placeholder from
// content. Before this, six files each carried their own copy of the rule and
// the model-output fallback spelled the placeholder a second way, so a section
// could count as filled in one place and empty in another.

/// The spellings as constants, for the handoff templates, which are constant
/// strings and so cannot read an enum's field.
const String notYetDeterminedText = '_Not yet determined._';
const String nothingYetText = '_Nothing yet._';

/// The text a handoff section holds when nothing real has been written to it.
enum HandoffPlaceholder {
  /// A section a later step is meant to fill: root cause, scope, constraints.
  notYetDetermined(notYetDeterminedText),

  /// A progress record with nothing recorded yet.
  nothingYet(nothingYetText);

  const HandoffPlaceholder(this.text);

  /// The exact text written into the handoff.
  final String text;

  /// Every placeholder, and the older spelling `_Not determined._`, starts
  /// with this; it is how a section is recognized as blank.
  static const String blankMarker = '_Not';

  /// Whether [section] holds no real content: it is empty or is a placeholder.
  static bool isBlank(String section) =>
      section.isEmpty || section.startsWith(blankMarker);
}
