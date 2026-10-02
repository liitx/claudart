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
  /// subprocess. Confirmed against a real Bedrock machine: detection is
  /// also fundamentally env-scoped — `claude` reads `~/.claude/settings.json`
  /// directly, which `detect()` cannot see, so a `null`/unsatisfied result
  /// is never proof a provider is absent.
  providerWiring(
    status: PortabilityGapStatus.open,
    whatsMissing:
        "AgentProvider exists (see docs/provider_setup.md) but isn't "
        'consulted before a real claude launch, and detect() cannot see '
        '~/.claude/settings.json — confirmed this would have produced a '
        'false negative gating a working Bedrock machine, which is part '
        'of why gating was never wired in',
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
  /// fresh-machine setup surface. `claudart doctor` ships tools/git-
  /// identity/gh-auth/provider-env; clones/git-perf/Zed-settings-merge
  /// still need the original zip's exact spec re-verified before they're
  /// implemented for real.
  verificationHarness(
    status: PortabilityGapStatus.open,
    whatsMissing:
        'claudart doctor (lib/commands/doctor.dart) covers tools-on-PATH, '
        'git identity, gh auth, and provider env. Still missing: clones, '
        'git-performance, and Zed-settings-merge checks — guessing at '
        'those risks encoding a wrong assumption as a passing check, so '
        "they're deferred until the original zip's Section 11 spec is "
        're-verified',
    trackedIn: 'lib/commands/doctor.dart, test/commands/doctor_test.dart',
  ),

  /// `pubspec.yaml`'s `dartrix` dependency is a relative path pointing at
  /// a sibling folder — `dart pub get` fails on a fresh clone until
  /// `liitx/dartrix` is cloned next to `claudart` manually. Confirmed by
  /// the agent testing this very PR: this was the first command that
  /// failed on their fresh checkout.
  dartrixSiblingDependency(
    status: PortabilityGapStatus.open,
    whatsMissing:
        'pubspec.yaml expects ../dartrix to already exist — dart pub get '
        'fails on a fresh clone with no setup instruction telling you to '
        'clone liitx/dartrix as a sibling first',
    trackedIn: 'pubspec.yaml',
  ),

  /// This repo's own `CLAUDE.md` hardcodes absolute paths
  /// (`/Users/aksana.buster/dev/apps/dartrix/...`,
  /// `/Users/aksana.buster/dev/dev_tools/claude/claudart/...`) that only
  /// resolve on the machine that wrote them.
  hardcodedWorkspacePaths(
    status: PortabilityGapStatus.open,
    whatsMissing:
        "CLAUDE.md's Paradigms pointer and Knowledge base section both "
        'hardcode this machine\'s absolute home-directory paths — a '
        'fresh clone on any other machine has to hand-edit CLAUDE.md '
        'before those references resolve',
    trackedIn: 'CLAUDE.md',
  ),

  /// Plain `dart analyze` (not `dart run custom_lint`) reports warnings
  /// for custom_lint rule names in `analysis_options.yaml` it doesn't
  /// recognize, because those rules are only registered when custom_lint
  /// itself runs.
  customLintWarningsUnderPlainAnalyze(
    status: PortabilityGapStatus.open,
    whatsMissing:
        'dart analyze alone surfaces 3 warnings for unrecognized '
        'custom_lint rule names in analysis_options.yaml — cosmetic '
        'noise on a fresh machine that runs dart analyze before ever '
        'running dart run custom_lint, easy to mistake for a real problem',
    trackedIn: 'analysis_options.yaml',
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
