// categorization.dart — typed taxonomy for agent task classification
//
// Three orthogonal axes form a Cartesian product:
//
//   T = AgentCategory × IntentClass × ComplexityTier
//     = 6 × 5 × 3 = 90 cells
//
// Model routing function:
//   τ : T → AgentModel  (total — exhaustive switch, Gap = ∅ by construction)
//
// Adding a new variant to any axis without updating τ is a compile error.
//
// Invariants (set-theoretic, from WorkStatus / BranchType pattern):
//   AgentCategory.feature.intents ∩ {IntentClass.document} = ∅
//   AgentCategory.research.intents ∩ {IntentClass.implement} = ∅
//   ComplexityTier.atomic ∩ ComplexityTier.systemic = ∅  (disjoint tiers)

import '../../util/enum_util.dart';
import '../agent_model.dart';
import '../xml_tags.dart';

/// Closed set of XML tags emitted by the categorize step. One enum
/// variant per slot, each carrying its wire-format tag name via
/// [wireTag]. Single source — planner log + route resolver + any
/// future consumer reference variants, not loose strings, so renaming
/// the wire format is one switch arm change.
///
/// Tag-name extraction is case-insensitive via [tagOrNullIgnoreCase]
/// because the LLM may not honor the system prompt's UPPER_SNAKE_CASE
/// convention.
enum CategorizeTag {
  category,
  intent,
  complexity,
  model;

  /// Wire-format tag name as emitted by the categorize system prompt.
  /// Exhaustive switch — adding a variant is a compile error until the
  /// arm is filled in.
  String get wireTag => switch (this) {
        CategorizeTag.category   => 'CATEGORY',
        CategorizeTag.intent     => 'INTENT',
        CategorizeTag.complexity => 'COMPLEXITY',
        CategorizeTag.model      => 'MODEL',
      };

  /// Extracts the trimmed content of this tag from [rawOutput]. Returns
  /// null when the tag is absent OR when its content is whitespace-only
  /// — `<CATEGORY></CATEGORY>` is treated identically to a missing tag
  /// so downstream `enumByName` lookups don't have to special-case the
  /// empty string.
  String? extractFrom(String rawOutput) {
    final content = tagOrNullIgnoreCase(rawOutput, wireTag);
    return (content == null || content.isEmpty) ? null : content;
  }

  /// The set of values the LLM may emit inside this tag. Drawn from the
  /// target enum's `.values` so renaming a variant on any axis
  /// propagates into the categorize prompt automatically — closing the
  /// prompt/parser drift seam that silently defeats `ComplexityTier`
  /// routing when the two get out of sync.
  ///
  /// Exhaustive switch — adding a CategorizeTag variant forces a new
  /// arm here at compile time.
  List<String> get allowedValues => switch (this) {
        CategorizeTag.category   =>
          [for (final v in AgentCategory.values) v.name],
        CategorizeTag.intent     =>
          [for (final v in IntentClass.values) v.name],
        CategorizeTag.complexity =>
          [for (final v in ComplexityTier.values) v.name],
        CategorizeTag.model      =>
          [for (final v in AgentModel.values) v.name],
      };
}

/// Assembles the categorize step's system prompt from the enum
/// taxonomy. Listing the tag names + allowed values explicitly tells
/// the LLM exactly what wire format to emit, AND keeps the prompt
/// structurally in sync with the parser via `CategorizeTag.values`.
///
/// Without this seam closed (slice 5 of the planner audit), an enum
/// rename produces silent fallback to sonnet for every task — the
/// LLM emits the old variant name, parsing fails, and PR #24's
/// `ComplexityTier`-driven routing is bypassed.
String buildCategorizePrompt() {
  // Each schema line is itself valid XML — `<TAG>one of: …</TAG>` —
  // so the LLM sees the actual wire format (open tag, content, close
  // tag) it must mirror at output time. The previous "<TAG>: v1, v2"
  // shape risked the model echoing the colon/no-closing-tag schema
  // line literally instead of producing a parseable `<TAG>v1</TAG>`.
  final schemaLines = [
    for (final tag in CategorizeTag.values)
      '<${tag.wireTag}>one of: ${tag.allowedValues.join(', ')}'
          '</${tag.wireTag}>',
  ].join('\n');
  // Tag count derives from `.values.length` so adding a CategorizeTag
  // variant updates the user-facing instruction automatically.
  final tagCount = CategorizeTag.values.length;
  return 'You are a precise task classifier. Classify the user input '
      'into exactly one value per axis below and emit each as an XML '
      'tag with matching open + close.\n\n'
      'Schema (mirror this exact wire format, substituting one value '
      'from each list):\n'
      '$schemaLines\n\n'
      'Output only the $tagCount XML tags — no prose, no markdown, '
      'no commentary outside the tags.';
}

// ── Axes ──────────────────────────────────────────────────────────────────────

/// What kind of work is being requested.
///
/// Invariant: active ∪ terminal = AgentCategory.values  (no uncategorised work)
enum AgentCategory {
  feature,   // new capability addition
  bug,       // defect investigation / repair
  refactor,  // structural improvement without behaviour change
  research,  // knowledge extraction / reference lookup
  setup,     // workspace or environment configuration
  gui;       // visual surface — widgets, painters, theme tokens

  /// Intent classes valid for this category.
  ///
  /// Invariant: feature.intents ∩ {IntentClass.document} = ∅
  /// Invariant: research.intents ∩ {IntentClass.implement} = ∅
  /// Invariant: gui.intents ⊆ {analyze, implement, design}
  Set<IntentClass> get intents => switch (this) {
        feature  => {IntentClass.explore, IntentClass.analyze, IntentClass.implement},
        bug      => {IntentClass.explore, IntentClass.analyze},
        refactor => {IntentClass.analyze, IntentClass.implement},
        research => {IntentClass.explore, IntentClass.document},
        setup    => {IntentClass.implement, IntentClass.document},
        gui      => {IntentClass.analyze, IntentClass.implement, IntentClass.design},
      };
}

/// What the agent is primarily doing within the task.
///
/// Partition: explore ∪ analyze ∪ implement ∪ document = IntentClass.values
enum IntentClass {
  explore,    // broad codebase or knowledge discovery
  analyze,    // reasoning over known, bounded context
  implement,  // code generation or modification
  document,   // structured output — reference, glossary, report
  design;     // visual surface review / spec generation
}

/// How broadly the task affects the codebase.
///
/// Partition: atomic ∪ compound ∪ systemic = ComplexityTier.values
/// Invariant: atomic ∩ systemic = ∅  (no task is both isolated and cross-cutting)
enum ComplexityTier {
  atomic,    // isolated — single file, clear scope, no cross-cutting concerns
  compound,  // multi-file — known dependencies, bounded blast radius
  systemic;  // cross-cutting — architectural impact, affects multiple subsystems
}

// ── Routing function ──────────────────────────────────────────────────────────

/// τ : AgentCategory × IntentClass × ComplexityTier → AgentModel
///
/// Total function — exhaustive switch over all 90 cells.
/// Three-layer rationale:
///   Theory:  opus excels at broad discovery; sonnet at reasoning + generation;
///            haiku at fast structured lookup.
///   Rule:    systemic × {explore,analyze} → opus;
///            * × {analyze,implement} → sonnet (unless systemic);
///            * × {explore,document} on atomic/compound → haiku.
///   Example: "explain how this codebase handles state" =
///            research × explore × systemic → opus.
AgentModel routeModel(
  AgentCategory category,
  IntentClass intent,
  ComplexityTier complexity,
) =>
    switch ((category, intent, complexity)) {
      // Systemic exploration or analysis always warrants maximum capability.
      (_, IntentClass.explore, ComplexityTier.systemic) ||
      (_, IntentClass.analyze, ComplexityTier.systemic) =>
        AgentModel.opus,

      // Any analysis or implementation at compound/atomic tier → balanced.
      // Compound exploration still benefits from balanced reasoning.
      // Visual design — balanced reasoning for spec generation at any tier.
      (_, IntentClass.analyze,   _) ||
      (_, IntentClass.implement, _) ||
      (_, IntentClass.explore,   ComplexityTier.compound) ||
      (_, IntentClass.design,    _) =>
        AgentModel.sonnet,

      // Atomic exploration and all documentation → fast lookup tier.
      (_, IntentClass.explore,  _) ||
      (_, IntentClass.document, _) =>
        AgentModel.haiku,
    };

/// Resolves an [AgentModel] from a categorize step's raw XML output by
/// extracting the three classification tags and consulting [routeModel].
/// Returns [fallback] when any tag is missing or maps to an unknown
/// enum variant — degrading gracefully per the reasoner's constraint
/// ("misrouting complex tasks to haiku is worse than full sonnet").
///
/// Wired into [AgentStep.modelSelector] for the plan step so the
/// categorize step's three-axis classification actually drives the
/// downstream model choice instead of being recorded and ignored.
AgentModel modelForCategorizeOutput(
  String rawOutput, {
  required AgentModel fallback,
}) {
  if (rawOutput.isEmpty) return fallback;
  final category = enumByName(
    AgentCategory.values,
    CategorizeTag.category.extractFrom(rawOutput),
  );
  final intent = enumByName(
    IntentClass.values,
    CategorizeTag.intent.extractFrom(rawOutput),
  );
  final complexity = enumByName(
    ComplexityTier.values,
    CategorizeTag.complexity.extractFrom(rawOutput),
  );
  if (category == null || intent == null || complexity == null) {
    return fallback;
  }
  return routeModel(category, intent, complexity);
}

// `enumByName` lives in `lib/util/enum_util.dart`. Local
// reimplementation here would defeat slice 2's dedupe and is a
// constraint violation per the planner audit. Import + use the
// canonical helper.
