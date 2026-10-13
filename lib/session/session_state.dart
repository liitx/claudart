import 'handoff_event.dart';
import 'teardown_utils.dart';

/// Typed representation of the handoff status field.
///
/// Replaces all magic string comparisons — the compiler enforces exhaustiveness
/// in switch expressions and catches typos at compile time.
enum HandoffStatus {
  suggestInvestigating,
  readyForSuggest,
  readyForDebug,
  debugInProgress,
  debugComplete,
  needsSuggest,

  /// Zedup-local: emitted when CLAUDART_PROJECT is unset or handoff.md absent.
  /// Never written to disk.
  noHandoff,

  unknown;

  static HandoffStatus fromString(String s) => switch (s) {
        'suggest-investigating' => suggestInvestigating,
        'ready-for-suggest'     => readyForSuggest,
        'ready-for-debug'       => readyForDebug,
        'debug-in-progress'     => debugInProgress,
        'debug-complete'        => debugComplete,
        'needs-suggest'         => needsSuggest,
        _                       => unknown,
      };

  /// The canonical string value written to and read from handoff.md.
  /// [noHandoff] and [unknown] are display-only — never written to disk.
  String get value => switch (this) {
        suggestInvestigating => 'suggest-investigating',
        readyForSuggest      => 'ready-for-suggest',
        readyForDebug        => 'ready-for-debug',
        debugInProgress      => 'debug-in-progress',
        debugComplete        => 'debug-complete',
        needsSuggest         => 'needs-suggest',
        noHandoff            => 'no-handoff',
        unknown              => 'unknown',
      };

  /// The status after [event] happens in this status, or null when
  /// docs/design.md's delta table has no such move (the move is rejected).
  HandoffStatus? after(HandoffEvent event) => switch ((event, this)) {
        (HandoffEvent.setup, noHandoff) ||
        (HandoffEvent.saveUnconfirmed, suggestInvestigating) ||
        (HandoffEvent.suggestResumed, needsSuggest) ||
        (HandoffEvent.rotated,
              suggestInvestigating || readyForDebug || debugInProgress) =>
          suggestInvestigating,
        (HandoffEvent.saveConfirmedExploring, suggestInvestigating) =>
          readyForSuggest,
        (HandoffEvent.saveConfirmedReady,
              suggestInvestigating ||
              readyForSuggest ||
              readyForDebug ||
              debugInProgress ||
              needsSuggest) =>
          readyForDebug,
        (HandoffEvent.saveUnconfirmed, debugInProgress) ||
        (HandoffEvent.debugStarted, readyForDebug) =>
          debugInProgress,
        (HandoffEvent.debugBlocked, debugInProgress) => needsSuggest,
        (HandoffEvent.fixApplied, readyForDebug || debugInProgress) =>
          debugComplete,
        (HandoffEvent.tornDown, debugComplete) ||
        (HandoffEvent.killed, _) when isPersisted =>
          noHandoff,
        _ => null,
      };

  /// True when `/debug` may start without an override: the root cause is
  /// locked (`readyForDebug`) or debug already began (`debugInProgress`).
  bool get canStartDebug => switch (this) {
        readyForDebug ||
        debugInProgress => true,
        suggestInvestigating ||
        readyForSuggest ||
        debugComplete ||
        needsSuggest ||
        noHandoff ||
        unknown => false,
      };

  /// False for the display-only variants that are never written to disk.
  bool get isPersisted => switch (this) {
        noHandoff ||
        unknown => false,
        suggestInvestigating ||
        readyForSuggest ||
        readyForDebug ||
        debugInProgress ||
        debugComplete ||
        needsSuggest => true,
      };

  /// Display label used in TUI status badges.
  String get label => value;

  /// True when the workflow expects `/suggest` next.
  bool get expectsSuggest => switch (this) {
        suggestInvestigating ||
        readyForSuggest ||
        needsSuggest ||
        noHandoff ||
        unknown => true,
        readyForDebug ||
        debugInProgress ||
        debugComplete => false,
      };

  /// True when the workflow expects `/debug` next.
  bool get expectsDebug => switch (this) {
        readyForDebug ||
        debugInProgress => true,
        suggestInvestigating ||
        readyForSuggest ||
        debugComplete ||
        needsSuggest ||
        noHandoff ||
        unknown => false,
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
