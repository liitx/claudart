// model_selection_agent.dart — regex-based natural language → categorization
//
// Parses freeform user input at the system boundary (the only place raw strings
// are compared) and maps it to typed (AgentCategory, IntentClass, ComplexityTier).
// All routing downstream uses the typed enums — no raw string comparisons inside
// commands (enum-first law from claudart knowledge_templates).
//
// Parse-once rule: called once at session start; typed result passed to executor.
//
// Regex patterns are const — no allocation per call.

import 'categorization.dart';

// ── Pattern tables ────────────────────────────────────────────────────────────

// Invariant: every pattern list is non-empty — each axis must be decidable.

final List<(RegExp, AgentCategory)> _categoryPatterns = [
  (RegExp(r'\b(add|new|creat|implement|introduc|build)\b', caseSensitive: false), AgentCategory.feature),
  (RegExp(r'\b(fix|bug|broken|crash|error|fail|defect|regression)\b', caseSensitive: false), AgentCategory.bug),
  (RegExp(r'\b(refactor|clean|restructur|reorgani|extract|simplif)\b', caseSensitive: false), AgentCategory.refactor),
  (RegExp(r'\b(explain|understand|how does|what is|research|look ?up|find)\b', caseSensitive: false), AgentCategory.research),
  (RegExp(r'\b(setup|configure|init|install|link|workspace)\b', caseSensitive: false), AgentCategory.setup),
];

final List<(RegExp, IntentClass)> _intentPatterns = [
  (RegExp(r'\b(explore|discover|survey|map|trace|find)\b', caseSensitive: false), IntentClass.explore),
  (RegExp(r'\b(analys|reason|understand|investigat|diagnos)\b', caseSensitive: false), IntentClass.analyze),
  (RegExp(r'\b(implement|creat|build|write|generat|produc)\b', caseSensitive: false), IntentClass.implement),
  (RegExp(r'\b(document|summarise|summarize|report|describe|explain)\b', caseSensitive: false), IntentClass.document),
];

final List<(RegExp, ComplexityTier)> _complexityPatterns = [
  (RegExp(r'\b(architect|cross.cutting|system.wide|all|entire|whole|everywhere)\b', caseSensitive: false), ComplexityTier.systemic),
  (RegExp(r'\b(multiple files?|several|across|span|depend)\b', caseSensitive: false), ComplexityTier.compound),
  (RegExp(r'\b(single|one file|small|quick|minor|trivial|isolated)\b', caseSensitive: false), ComplexityTier.atomic),
];

// ── ClassificationResult ──────────────────────────────────────────────────────

final class ClassificationResult {
  final AgentCategory category;
  final IntentClass intent;
  final ComplexityTier complexity;

  const ClassificationResult({
    required this.category,
    required this.intent,
    required this.complexity,
  });

  @override
  String toString() =>
      '${category.name} × ${intent.name} × ${complexity.name}';
}

// ── ModelSelectionAgent ───────────────────────────────────────────────────────

/// Classifies freeform input into (AgentCategory, IntentClass, ComplexityTier)
/// and resolves the preferred AgentModel via τ.
///
/// Defaults when no pattern matches:
///   category   → research  (safest — discover before acting)
///   intent     → explore   (broad first)
///   complexity → compound  (mid-tier avoids over/under-resourcing)
abstract final class ModelSelectionAgent {
  ModelSelectionAgent._();

  /// Classifies [input] against regex pattern tables.
  static ClassificationResult classify(String input) {
    final AgentCategory category = _match(input, _categoryPatterns) ?? AgentCategory.research;
    IntentClass   intent        = _match(input, _intentPatterns)    ?? IntentClass.explore;
    final ComplexityTier complexity = _match(input, _complexityPatterns) ?? ComplexityTier.compound;

    // Enforce category × intent invariants:
    //   feature.intents ∩ {document} = ∅ → clamp to explore
    //   research.intents ∩ {implement} = ∅ → clamp to explore
    if (!category.intents.contains(intent)) {
      intent = category.intents.first;
    }

    return ClassificationResult(
      category:   category,
      intent:     intent,
      complexity: complexity,
    );
  }

  static T? _match<T>(String input, List<(RegExp, T)> patterns) {
    for (final (pattern, value) in patterns) {
      if (pattern.hasMatch(input)) return value;
    }
    return null;
  }
}
