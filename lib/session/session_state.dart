import 'handoff_event.dart';
import 'handoff_finding.dart';
import 'handoff_section.dart';
import 'knowledge_transfer.dart';
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
  /// Exhaustive over event and status: every illegal cell is an explicit null.
  HandoffStatus? after(HandoffEvent event) => switch (event) {
        HandoffEvent.setup => switch (this) {
            noHandoff => suggestInvestigating,
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            debugComplete ||
            needsSuggest ||
            unknown =>
              null,
          },
        HandoffEvent.saveUnconfirmed => switch (this) {
            suggestInvestigating => suggestInvestigating,
            debugInProgress => debugInProgress,
            readyForSuggest ||
            readyForDebug ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.saveConfirmedExploring => switch (this) {
            suggestInvestigating => readyForSuggest,
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.saveConfirmedReady => switch (this) {
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            needsSuggest =>
              readyForDebug,
            debugComplete ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.debugStarted => switch (this) {
            readyForDebug => debugInProgress,
            suggestInvestigating ||
            readyForSuggest ||
            debugInProgress ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.debugBlocked => switch (this) {
            debugInProgress => needsSuggest,
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.suggestResumed => switch (this) {
            needsSuggest => suggestInvestigating,
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            debugComplete ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.fixApplied => switch (this) {
            readyForDebug ||
            debugInProgress =>
              debugComplete,
            suggestInvestigating ||
            readyForSuggest ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.rotated => switch (this) {
            suggestInvestigating ||
            readyForDebug ||
            debugInProgress =>
              suggestInvestigating,
            readyForSuggest ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.rotatedEmpty => switch (this) {
            suggestInvestigating ||
            readyForDebug ||
            debugInProgress =>
              noHandoff,
            readyForSuggest ||
            debugComplete ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.tornDown => switch (this) {
            debugComplete => noHandoff,
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            needsSuggest ||
            noHandoff ||
            unknown =>
              null,
          },
        HandoffEvent.reminderSaved || HandoffEvent.killed => switch (this) {
            suggestInvestigating ||
            readyForSuggest ||
            readyForDebug ||
            debugInProgress ||
            debugComplete ||
            needsSuggest =>
              noHandoff,
            noHandoff ||
            unknown =>
              null,
          },
      };

  /// What the owner should do next from this status. One text per status, so
  /// `status`, a rejected command and any later reader say the same thing.
  String get nextStep => switch (this) {
        suggestInvestigating => 'Run /suggest in your editor.',
        readyForSuggest => 'Run /suggest in your editor to begin a new cycle.',
        readyForDebug => 'Run /debug in your editor.',
        debugInProgress =>
          'Continue with /debug, or run /suggest if you hit a wall.',
        debugComplete => 'Verify with dart test, then claudart teardown to '
            'keep what was learned, or claudart rotate for the next issue.',
        needsSuggest =>
          'Run /suggest in your editor — debug has a question for you.',
        noHandoff || unknown => 'Run: claudart setup',
      };

  /// What this status claims about the handoff's knowledge transfer: the four
  /// statuses after the root cause is confirmed say it is complete, the one
  /// still investigating says it is not. `needsSuggest` says nothing: debug has
  /// a question, and the root cause it was given is still in the file.
  KnowledgeTransferExpectation get knowledgeTransferExpectation =>
      switch (this) {
        readyForSuggest ||
        readyForDebug ||
        debugInProgress ||
        debugComplete =>
          KnowledgeTransferExpectation.converged,
        suggestInvestigating => KnowledgeTransferExpectation.unconverged,
        needsSuggest ||
        noHandoff ||
        unknown =>
          KnowledgeTransferExpectation.none,
      };

  /// What `kill` would lose from this status, or null when it loses nothing.
  /// A finished fix is the one status whose learning only `teardown` keeps.
  String? get killWarning => switch (this) {
        debugComplete => 'The fix is applied. kill does not update skills.md, '
            'so nothing from this session is learned; claudart teardown keeps '
            'it.',
        suggestInvestigating ||
        readyForSuggest ||
        readyForDebug ||
        debugInProgress ||
        needsSuggest ||
        noHandoff ||
        unknown =>
          null,
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

  /// True when the workflow expects `/debug` next. The same set as
  /// [canStartDebug]: one definition, kept as a named alias because zedup's
  /// workflow gating reads it.
  bool get expectsDebug => canStartDebug;
}

/// Read-only structured view of a handoff.md file.
///
/// Parsed once at command startup; never mutated. Callers use this to
/// display session context before destructive operations like `kill`.
class SessionState {
  final HandoffStatus status;
  final String branch;
  final HandoffSection bug;
  final HandoffSection rootCause;
  final HandoffSection scope;
  final HandoffSection attempted;
  final HandoffSection changed;
  final HandoffSection unresolved;

  const SessionState({
    required this.status,
    required this.branch,
    required this.bug,
    required this.rootCause,
    required this.scope,
    required this.attempted,
    required this.changed,
    required this.unresolved,
  });

  /// Returns true if the handoff contains non-placeholder content in any
  /// meaningful field — i.e., the session was actually started.
  bool get hasActiveContent =>
      !bug.isBlank || !rootCause.isBlank || !attempted.isBlank;

  /// The status a consumer should show: [status] when the handoff holds a real
  /// session, [HandoffStatus.noHandoff] when it does not. The blank handoff
  /// that kill, teardown and an empty rotate leave behind still has a
  /// `suggest-investigating` Status line, but it is not a session; reading
  /// [status] alone would present it as one. Every consumer (claudart's
  /// commands, zedup) should read this, so they cannot disagree.
  HandoffStatus get effectiveStatus =>
      hasActiveContent ? status : HandoffStatus.noHandoff;

  /// Whether the content is a complete knowledge transfer, read from the root
  /// cause and the scope and not from the status.
  KnowledgeTransfer get knowledgeTransfer =>
      KnowledgeTransfer.of(rootCause: rootCause, scope: scope);

  /// How the status and the content disagree; empty for a consistent handoff.
  List<HandoffFinding> get findings => switch ((
        effectiveStatus.knowledgeTransferExpectation,
        knowledgeTransfer,
      )) {
        (
          KnowledgeTransferExpectation.converged,
          KnowledgeTransfer.unconverged,
        ) =>
          [HandoffFinding.statusAheadOfContent],
        (
          KnowledgeTransferExpectation.unconverged,
          KnowledgeTransfer.converged,
        ) =>
          [HandoffFinding.contentAheadOfStatus],
        (KnowledgeTransferExpectation.converged, KnowledgeTransfer.converged) ||
        (
          KnowledgeTransferExpectation.unconverged,
          KnowledgeTransfer.unconverged,
        ) ||
        (KnowledgeTransferExpectation.none, KnowledgeTransfer.converged) ||
        (KnowledgeTransferExpectation.none, KnowledgeTransfer.unconverged) =>
          const [],
      };

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
      bug: HandoffSection(_clean(extractSection(content, 'Bug'))),
      rootCause: HandoffSection(_clean(extractSection(content, 'Root Cause'))),
      scope: HandoffSection(
        readSubSection(extractSection(content, 'Scope'), 'Files in play'),
      ),
      attempted: HandoffSection(
        readSubSection(debugProgress, 'What was attempted'),
      ),
      changed: HandoffSection(
        readSubSection(debugProgress, 'What changed (files modified)'),
      ),
      unresolved: HandoffSection(
        readSubSection(debugProgress, 'What is still unresolved'),
      ),
    );
  }

  /// Strips trailing horizontal rule (`---`) left by [extractSection] and trims.
  static String _clean(String s) =>
      s.replaceAll(RegExp(r'\n*-{3,}\s*$'), '').trim();
}
