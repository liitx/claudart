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
  providerEnv,

  /// `CLAUDART_WORKSPACE` is set in this process's own environment —
  /// surfaces the split-brain-registry failure mode directly (a process
  /// that doesn't inherit a shell's exported override silently falls
  /// back to `~/.claudart`, which can diverge from the real one) instead
  /// of requiring someone to notice two registries by hand.
  workspaceRoot,

  /// Every entry in the active registry still points at a `projectRoot`
  /// that exists on disk — a stale entry (deleted/moved project) is
  /// exactly the kind of drift a fresh-machine migration needs surfaced,
  /// not silently carried forward.
  registryHealth,

  /// `~/bin` (where both `claudart compile` and `zedup setup` install to)
  /// is actually on PATH — otherwise a freshly-compiled binary is
  /// unreachable without the user noticing why `claudart`/`zedup` isn't
  /// found.
  pathConfiguration,

  /// When Bedrock is the active provider, `AWS_EC2_METADATA_DISABLED` must
  /// be `true` unless this machine is a real EC2 host. Measured directly
  /// (`OAUTH-BEDROCK-FINAL-REPORT.md`): without it, a Bedrock profile that
  /// cannot supply credentials doesn't fail fast — the AWS SDK falls
  /// through to probing the EC2 instance metadata service and stalls for
  /// minutes (740s measured) before erroring, which looks exactly like a
  /// hang to anyone watching.
  bedrockMetadataDisabled,

  /// When Bedrock is the active provider, a bounded `aws sts
  /// get-caller-identity` call confirms credentials actually resolve
  /// before anything spawns `claude` against them — "Bedrock configured"
  /// (env vars present) is not the same fact as "Bedrock will work".
  bedrockCredentialsPreflight,

  /// `core.hooksPath` points at this project's tracked `.githooks/` when
  /// one exists — `.git/hooks/` is never committed, so a project with a
  /// real pre-push paradigm gate still ships it to nobody on a fresh
  /// clone unless this is configured. `claudart link` sets it
  /// automatically; this check catches a project linked before that, or
  /// linked by a non-claudart tool.
  gitHooksConfigured,

  /// Every `ClaudartArtifact` for the current project's `link` output is
  /// `fresh` or `notApplicable` — a `stale`/`missing` one means a source
  /// (pubspec.yaml, roadmap.json, generic knowledge files) changed since
  /// the last `claudart link` and the generated output hasn't caught up.
  artifactFreshness;

  String get label => switch (this) {
        HarnessCheckId.tools                      => 'tools',
        HarnessCheckId.gitIdentity                => 'git identity',
        HarnessCheckId.ghAuth                      => 'gh auth',
        HarnessCheckId.providerEnv                 => 'provider env',
        HarnessCheckId.workspaceRoot               => 'workspace root',
        HarnessCheckId.registryHealth              => 'registry health',
        HarnessCheckId.pathConfiguration           => 'path configuration',
        HarnessCheckId.bedrockMetadataDisabled     => 'bedrock metadata guard',
        HarnessCheckId.bedrockCredentialsPreflight => 'bedrock credentials',
        HarnessCheckId.gitHooksConfigured          => 'git hooks',
        HarnessCheckId.artifactFreshness            => 'artifact freshness',
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
