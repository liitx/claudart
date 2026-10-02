// portability_gap.dart — typed discrepancy ledger
//
// README_PORTABILITY.md's "Known portability gaps" table was hand-written
// prose the first time it was drafted — exactly the kind of bare,
// duplicated-across-files string this project's own paradigm forbids.
// Each row is now a PortabilityGapStatus-stamped enum variant instead, so
// the table (and any future consumer — a `claudart doctor` command, a
// test asserting the docs haven't drifted) reads from one typed source.
//
// Invariants:
//   for all g: g.whatsMissing.isNotEmpty
//   for all g: g.trackedIn.isNotEmpty
//   gaps close over time — when one ships, delete its variant and its
//   README_PORTABILITY.md row together, don't leave either behind.

/// Where a gap currently stands.
enum PortabilityGapStatus {
  /// A primitive/building block exists in code but isn't consulted yet by
  /// the real call site it's meant to guard.
  open,

  /// Explicitly deferred — no second concrete target exists to generalize
  /// against yet; building for a hypothetical one would be premature.
  tabled,

  /// Scoped and sequenced, but not started.
  planned;

  String get label => switch (this) {
        PortabilityGapStatus.open    => 'open',
        PortabilityGapStatus.tabled  => 'tabled',
        PortabilityGapStatus.planned => 'planned',
      };
}

enum PortabilityGap {
  /// `AgentProvider` (lib/providers/agent_provider.dart) exists but isn't
  /// consulted before `defaultClaudeRunner` spawns the real `claude`
  /// subprocess.
  providerWiring(
    status: PortabilityGapStatus.open,
    whatsMissing:
        "AgentProvider exists (see docs/provider_setup.md) but isn't "
        'consulted before a real claude launch',
    trackedIn: 'docs/provider_setup.md',
  ),

  /// `lib/commands/link.dart` creates `.claude/commands` and
  /// `.cursor/commands` only — zero Zed-editor-specific scaffolding.
  zedEditorIntegration(
    status: PortabilityGapStatus.tabled,
    whatsMissing:
        'lib/commands/link.dart creates .claude/commands and '
        '.cursor/commands only — zero Zed-editor-specific scaffolding, '
        "despite one real machine depending on Zed's own settings.json "
        'for its entire Bedrock auth chain',
    trackedIn:
        'tabled — no second real IDE target to generalize against yet; '
        'building for a hypothetical one would be premature abstraction',
  ),

  /// `ZedProfile` was checked and confirmed to be org identity
  /// (liitx/toyota), not IDE coupling — the real Zed-editor seam is the
  /// narrow `ZedHelper.zedLauncher`.
  zedupEnvWorkspaceResolution(
    status: PortabilityGapStatus.tabled,
    whatsMissing:
        'ZedProfile (zedup) is not actually IDE coupling — confirmed by '
        'reading it directly, it is liitx-vs-toyota org identity (branch '
        'types, PR templates, GitHub owners). The one real Zed-editor '
        'seam is narrow: ZedHelper.zedLauncher, which launches the zed '
        'binary. Do not conflate the two when scoping this',
    trackedIn: 'tabled alongside zedEditorIntegration',
  ),

  /// The Section 11 harness spec from the original machine-setup zip:
  /// idempotent, [OK]/[SKIP]/[FAIL]-logging checks across the whole
  /// fresh-machine setup surface.
  verificationHarness(
    status: PortabilityGapStatus.planned,
    whatsMissing:
        'An idempotent, [OK]/[SKIP]/[FAIL]-logging script covering '
        'tools/SSH/gitconfig/gh auth/clones/git perf/Zed-settings-merge/'
        'provider-env/verification pass — scoped, not yet built',
    trackedIn:
        'planned next, dependency-ordered after providerWiring and the '
        'IDE-coupling gaps',
  );

  const PortabilityGap({
    required this.status,
    required this.whatsMissing,
    required this.trackedIn,
  });

  /// Where this gap currently stands.
  final PortabilityGapStatus status;

  /// What's missing — the gap itself, in prose.
  final String whatsMissing;

  /// Where this gap is tracked / why it's at its current status.
  final String trackedIn;
}
