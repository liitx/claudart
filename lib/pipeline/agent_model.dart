// agent_model.dart — typed Anthropic model registry
//
// Every model used by claudart is a first-class enum value — never a magic
// string. Adding a new model forces all exhaustive switches to update;
// the compiler enforces coverage.
//
// Consolidates zedup's ClaudartModel — when zedup imports claudart's library,
// ClaudartModel is retired and replaced by AgentModel.
//
// Delegation profile — this is AgentFlow.preferredModel's flow-level
// choice (one model per whole flow, e.g. zedup's single-shot chat
// dispatch), not a rule for routing within a flow's own batched pipeline:
//   capable  → suggest        (deep reasoning, root cause analysis)
//   balanced → debug / flow   (precise instruction following, minimal diff)
//   fast     → research       (constrained lookup, single reference doc)
//
// Individual steps inside a batched pipeline (suggest_steps.dart's
// reader/reasoner/planner/lookup/applier, etc.) pick their own model per
// step to control cost across the whole pipeline — they are not bound by
// this table, and mostly stay at fast/balanced even where the flow-level
// preferredModel above is capable. See AgentModel.bestForLookup /
// bestForAnalysis / bestForExplore for the canonical model each of those
// three task types resolves to. Identity-based, not tier-derived: fable
// shares ModelTier.capable with opus (same general capability class) but
// is a distinct specialization for IntentClass.design work
// (categorization.dart's routeModel), not a fourth bestFor* task type.
//
// Update (2026-09-27): categorization.dart's routeModel now routes
// IntentClass.design to opus, not fable — reconsidered after comparing
// design/architecture output quality directly. fable stays registered
// (a real, valid model) but isn't the default route for anything today;
// the identity-based bestFor* predicates above remain correct regardless
// of which model design routes to.

// ── ModelTier ─────────────────────────────────────────────────────────────────

/// Capability tier used for delegation routing.
/// Drives which tasks each model is best suited for.
enum ModelTier {
  /// Fastest, cheapest — constrained lookups and mechanical transforms.
  fast,

  /// Speed-accuracy balance — precise implementation and structured output.
  balanced,

  /// Most capable — deep exploration and root cause analysis.
  capable;

  String get label => switch (this) {
        ModelTier.fast     => 'fast',
        ModelTier.balanced => 'balanced',
        ModelTier.capable  => 'capable',
      };
}

// ── AgentModel ────────────────────────────────────────────────────────────────

enum AgentModel {
  /// claude-haiku — fastest, lowest cost.
  /// Pipeline roles: reader (file scan), lookup (targeted search), applier (XML surgery).
  haiku(
    alias:           'haiku',
    slug:            'claude-haiku-4-5-20251001',
    shortName:       'haiku-4.5',
    contextWindow:   200000,
    maxOutputTokens: 8192,
    tier:            ModelTier.fast,
  ),

  /// claude-sonnet — balanced speed and precision.
  /// Pipeline roles: reasoner (analysis), planner (change planning), debug.
  sonnet(
    alias:           'sonnet',
    slug:            'claude-sonnet-5-5',
    shortName:       'sonnet-5',
    contextWindow:   200000,
    maxOutputTokens: 16000,
    tier:            ModelTier.balanced,
  ),

  /// claude-opus — most capable.
  /// Pipeline roles: suggest (deep root cause), complex multi-file reasoning.
  opus(
    alias:           'opus',
    slug:            'claude-opus-5-5',
    shortName:       'opus-5.5',
    contextWindow:   200000,
    maxOutputTokens: 32000,
    tier:            ModelTier.capable,
  ),

  /// claude-fable — a design-oriented model. Same general capability
  /// class as opus (tier: capable). Originally routed here by
  /// `routeModel` for `IntentClass.design` work: visual surface review,
  /// spec generation, architecture/UX design.
  ///
  /// Update (2026-09-27): `routeModel` now routes design work to opus
  /// instead, after directly comparing output quality — opus is the
  /// stronger designer. fable remains a real, valid model in this
  /// registry but is not the default route for anything today; use it
  /// only when explicitly requested by name.
  fable(
    alias:           'fable',
    slug:            'claude-fable-5-1',
    shortName:       'fable-5.1',
    contextWindow:   200000,
    maxOutputTokens: 32000,
    tier:            ModelTier.capable,
  );

  const AgentModel({
    required this.alias,
    required this.slug,
    required this.shortName,
    required this.contextWindow,
    required this.maxOutputTokens,
    required this.tier,
  });

  /// Value passed to the `--model` CLI flag.
  final String alias;

  /// Exact string used in the Anthropic API `model` field.
  final String slug;

  /// Short display name shown in TUI status and test output.
  final String shortName;

  /// Maximum input context in tokens.
  final int contextWindow;

  /// Maximum generated tokens per call.
  final int maxOutputTokens;

  /// Capability tier — drives delegation routing.
  final ModelTier tier;

  // ── Predicates ───────────────────────────────────────────────────────────────

  // Identity-based, not tier-derived: fable also sits at ModelTier.capable
  // (same general capability class as opus) but isn't the explore/analysis
  // choice — it's a distinct specialization routed via `routeModel`'s
  // design branch instead. Deriving these from tier would make fable
  // falsely bestForExplore alongside opus, breaking the "exactly one
  // model per task" invariant these predicates exist to guarantee.
  bool get bestForLookup    => this == AgentModel.haiku;
  bool get bestForAnalysis  => this == AgentModel.sonnet;
  bool get bestForExplore   => this == AgentModel.opus;

  // ── Parsing ──────────────────────────────────────────────────────────────────

  /// Resolves an alias string ('haiku', 'sonnet', 'opus') to [AgentModel].
  /// Returns null for unrecognised aliases (forward-compatible).
  static AgentModel? fromAlias(String value) {
    for (final m in values) {
      if (m.alias == value) return m;
    }
    return null;
  }

  /// Resolves an API slug to [AgentModel].
  /// Returns null for unrecognised slugs (forward-compatible).
  static AgentModel? fromSlug(String value) {
    for (final m in values) {
      if (m.slug == value) return m;
    }
    return null;
  }
}
