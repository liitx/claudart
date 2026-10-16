/// What happened to a session, named by outcome. Together with
/// `HandoffStatus.after` this is the transition function (delta) of
/// docs/design.md: every status change goes through it.
enum HandoffEvent {
  /// `claudart setup` wrote a fresh handoff.
  setup,

  /// `/save` with the root cause still unconfirmed (state unchanged).
  saveUnconfirmed,

  /// `/save` with the root cause confirmed and more exploration expected.
  saveConfirmedExploring,

  /// `/save` or `/suggest` approved: root cause confirmed, ready to implement.
  saveConfirmedReady,

  /// `/debug` started implementing.
  debugStarted,

  /// Debug hit a question only suggest can resolve.
  debugBlocked,

  /// `/suggest` picked up a blocked handoff.
  suggestResumed,

  /// `/debug` applied its plan. docs/design.md names the exit "fix verified";
  /// claudart does not verify, so the event is named for what it does.
  fixApplied,

  /// `claudart rotate` archived this session and seeded the next.
  rotated,

  /// `claudart rotate` archived this session with no pending issue to seed,
  /// so the handoff was reset to blank.
  rotatedEmpty,

  /// `claudart teardown` closed a completed session.
  tornDown,

  /// `claudart teardown` found the session unresolved, saved it as a reminder
  /// and reset the handoff.
  reminderSaved,

  /// `claudart kill` abandoned the session.
  killed,
}
