import '../teardown_utils.dart';

/// Typed representation of the handoff status field.
///
/// Replaces all magic string comparisons — the compiler enforces exhaustiveness
/// in switch expressions and catches typos at compile time.
enum HandoffStatus {
  suggestInvestigating,
  readyForDebug,
  debugInProgress,
  needsSuggest,
  unknown;

  static HandoffStatus fromString(String s) => switch (s) {
        'suggest-investigating' => suggestInvestigating,
        'ready-for-debug' => readyForDebug,
        'debug-in-progress' => debugInProgress,
        'needs-suggest' => needsSuggest,
        _ => unknown,
      };

  /// The canonical string value written to and read from handoff.md.
  String get value => switch (this) {
        suggestInvestigating => 'suggest-investigating',
        readyForDebug => 'ready-for-debug',
        debugInProgress => 'debug-in-progress',
        needsSuggest => 'needs-suggest',
        unknown => 'unknown',
      };
}

/// Read-only structured view of a handoff.md file.
///
/// Parsed once at command startup; never mutated. Callers use this to
/// display session context before destructive operations like `kill`.
class SessionState {
  final HandoffStatus status;
  final String branch;
  final String bug;
  final String rootCause;
  final String attempted;
  final String changed;
  final String unresolved;

  const SessionState({
    required this.status,
    required this.branch,
    required this.bug,
    required this.rootCause,
    required this.attempted,
    required this.changed,
    required this.unresolved,
  });

  /// Returns true if the handoff contains non-placeholder content in any
  /// meaningful field — i.e., the session was actually started.
  bool get hasActiveContent =>
      !_isBlank(bug) || !_isBlank(rootCause) || !_isBlank(attempted);

  static bool _isBlank(String s) =>
      s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');

  /// Parses [content] from a handoff.md file into a [SessionState].
  ///
  /// Missing sections become empty strings; placeholder text is preserved
  /// as-is so [hasActiveContent] can distinguish a fresh handoff from one
  /// with real work recorded.
  factory SessionState.parse(String content) {
    final debugProgress = extractSection(content, 'Debug Progress');
    return SessionState(
      status: HandoffStatus.fromString(_clean(extractSection(content, 'Status'))),
      branch: extractBranch(content),
      bug: _clean(extractSection(content, 'Bug')),
      rootCause: _clean(extractSection(content, 'Root Cause')),
      attempted: readSubSection(debugProgress, 'What was attempted'),
      changed: readSubSection(debugProgress, 'What changed (files modified)'),
      unresolved: readSubSection(debugProgress, 'What is still unresolved'),
    );
  }

  /// Strips trailing horizontal rule (`---`) left by [extractSection] and trims.
  static String _clean(String s) =>
      s.replaceAll(RegExp(r'\n*-{3,}\s*$'), '').trim();
}
