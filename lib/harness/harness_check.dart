// harness_check.dart — typed identity for `claudart doctor`'s checks
//
// The fresh-machine verification harness from the original machine-setup
// zip's Section 11 spec: idempotent, one-line [OK]/[SKIP]/[FAIL] checks.
// This enum is the typed backbone — no bare strings for either the check
// identity or its outcome marker.
//
// Scope note: Section 11 also specified clones/git-performance/Zed-
// settings-merge checks. Those need the original zip's exact spec
// re-verified before being implemented — guessing at them risks encoding
// a wrong assumption as a "passing" check. See PortabilityGap.verificationHarness.

/// Identity of a single harness check. Adding a variant forces a new arm
/// in `doctor.dart`'s exhaustive check-dispatch switch at compile time.
enum HarnessCheckId {
  /// `git`, `gh`, and `claude` are all reachable on PATH.
  tools,

  /// `git config user.name`/`user.email` are set for the current repo.
  gitIdentity,

  /// `gh auth status` reports an active login.
  ghAuth,

  /// `AgentProvider.detect` finds a configured provider, or none is
  /// required (ambient OAuth login is a valid, unconfigured state).
  providerEnv;

  String get label => switch (this) {
        HarnessCheckId.tools       => 'tools',
        HarnessCheckId.gitIdentity => 'git identity',
        HarnessCheckId.ghAuth      => 'gh auth',
        HarnessCheckId.providerEnv => 'provider env',
      };
}

/// Outcome of a single harness check.
enum HarnessCheckResult {
  ok,
  skip,
  fail;

  String get marker => switch (this) {
        HarnessCheckResult.ok   => '[OK]',
        HarnessCheckResult.skip => '[SKIP]',
        HarnessCheckResult.fail => '[FAIL]',
      };
}

/// One check's result: which check, what happened, and why.
typedef HarnessCheckOutcome = ({
  HarnessCheckId id,
  HarnessCheckResult result,
  String detail,
});

/// Renders a single outcome as one `[OK] tools: ...`-style log line.
String formatHarnessOutcome(HarnessCheckOutcome outcome) =>
    '${outcome.result.marker} ${outcome.id.label}: ${outcome.detail}';
