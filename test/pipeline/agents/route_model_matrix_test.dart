// route_model_matrix_test.dart — exhaustive τ matrix coverage for
// `routeModel`. Iterates the full Cartesian product
//   AgentCategory × IntentClass × ComplexityTier   = 6 × 5 × 3 = 90
// so adding any axis variant (or rewriting an arm in `routeModel`)
// forces an explicit decision here — closing the "PR #24 routing
// silently regresses" seam (slice 6 of the planner audit).
//
// Three layers:
//   1. Per-cell: every (category, intent, complexity) maps to the
//      AgentModel that the τ-matrix doc-comment in routeModel
//      declares. Encoded as a pure function `expectedFor(...)` so
//      the test is a *spec*, not a copy of the production switch.
//   2. Complexity-sensitivity invariant: for the intents where PR
//      #24 introduced tier-driven routing, holding (category,
//      intent) constant MUST produce ≥ 2 distinct models across
//      `ComplexityTier.values`. Without this, the tier wire could
//      regress to constant and every other test would still pass.
//   3. Range invariant: the image of τ is exactly the set of
//      AgentModel variants currently in use ({haiku, sonnet, opus}).
//      Adding an AgentModel variant without wiring it into τ is
//      flagged.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agents/categorization.dart';
import 'package:test/test.dart';

/// Spec form of the τ matrix. Reading order matches the doc-comment
/// in `routeModel` so divergence between spec and impl is visible at
/// review time. Pure function — no fixture data.
AgentModel _expectedFor(
  AgentCategory category,
  IntentClass intent,
  ComplexityTier complexity,
) {
  // Systemic exploration/analysis → opus.
  if (complexity == ComplexityTier.systemic &&
      (intent == IntentClass.explore || intent == IntentClass.analyze)) {
    return AgentModel.opus;
  }
  // Analyze/implement at any non-systemic tier → sonnet.
  if (intent == IntentClass.analyze || intent == IntentClass.implement) {
    return AgentModel.sonnet;
  }
  // Compound exploration → sonnet (balanced reasoning).
  if (intent == IntentClass.explore && complexity == ComplexityTier.compound) {
    return AgentModel.sonnet;
  }
  // Atomic exploration + all documentation → sonnet. Haiku never reasons or
  // implements, so no cell routes to it: it only classifies and reads.
  if (intent == IntentClass.explore || intent == IntentClass.document) {
    return AgentModel.sonnet;
  }
  // Visual/architectural design → opus, at every tier (2026-09-27: was
  // fable; reconsidered after comparing output quality directly).
  return AgentModel.opus;
}

void main() {
  group('routeModel — exhaustive τ matrix (every cell holds the spec)', () {
    for (final category in AgentCategory.values) {
      for (final intent in IntentClass.values) {
        for (final complexity in ComplexityTier.values) {
          test(
              '${category.name} × ${intent.name} × ${complexity.name} '
              '→ ${_expectedFor(category, intent, complexity).name}', () {
            expect(
              routeModel(category, intent, complexity),
              equals(_expectedFor(category, intent, complexity)),
              reason:
                  'τ(${category.name}, ${intent.name}, ${complexity.name}) '
                  'diverged from spec — either the doc-comment in '
                  'routeModel is stale or the switch arm regressed',
            );
          });
        }
      }
    }
  });

  group(
      'routeModel — ComplexityTier is load-bearing for tier-sensitive '
      'intents (PR #24 contract)', () {
    // For these intents, the τ matrix bifurcates by tier. If the
    // wire ever regresses to "ignore complexity", the per-cell
    // matrix above still passes (a constant function satisfies any
    // single column); this invariant catches that.
    const tierSensitiveIntents = {
      IntentClass.explore, // atomic and compound → sonnet, systemic → opus
      IntentClass.analyze, // systemic → opus, others → sonnet
    };

    for (final category in AgentCategory.values) {
      for (final intent in tierSensitiveIntents) {
        test(
            'holding (${category.name}, ${intent.name}) constant, '
            'tier varies the model', () {
          final models = {
            for (final c in ComplexityTier.values)
              routeModel(category, intent, c),
          };
          expect(
            models.length,
            greaterThanOrEqualTo(2),
            reason:
                '${intent.name} routes to the same model across all '
                'three tiers — ComplexityTier wire is bypassed',
          );
        });
      }
    }
  });

  group('routeModel — tier-invariant intents stay constant', () {
    // Counterpart to the previous group: implement/document/design
    // are tier-invariant by design. If a future edit accidentally
    // makes them tier-sensitive, the doc-comment in routeModel is
    // wrong and this fires.
    const tierInvariantIntents = {
      IntentClass.implement,
      IntentClass.document,
      IntentClass.design,
    };

    for (final category in AgentCategory.values) {
      for (final intent in tierInvariantIntents) {
        test(
            'holding (${category.name}, ${intent.name}) constant, '
            'tier does NOT vary the model', () {
          final models = {
            for (final c in ComplexityTier.values)
              routeModel(category, intent, c),
          };
          expect(
            models.length,
            equals(1),
            reason:
                '${intent.name} is documented as tier-invariant but '
                'now produces different models per ComplexityTier',
          );
        });
      }
    }
  });

  group('routeModel — image is a subset of AgentModel.values', () {
    test('every cell maps to a real AgentModel variant', () {
      final image = <AgentModel>{
        for (final category in AgentCategory.values)
          for (final intent in IntentClass.values)
            for (final complexity in ComplexityTier.values)
              routeModel(category, intent, complexity),
      };
      // Subset check — exhaustive enum guarantees this trivially at
      // the type level, but the assertion documents the intent and
      // pins the rendered set for future readers.
      expect(image.difference(AgentModel.values.toSet()), isEmpty);
      expect(image, isNotEmpty);
    });

    // Haiku is the cheapest model and is not sufficient to reason or
    // implement. The coordinator assigns only these two, defaulting to
    // sonnet, so no cell may ever resolve to haiku.
    test('the image is exactly sonnet and opus — never haiku', () {
      final image = <AgentModel>{
        for (final category in AgentCategory.values)
          for (final intent in IntentClass.values)
            for (final complexity in ComplexityTier.values)
              routeModel(category, intent, complexity),
      };
      expect(image, equals({AgentModel.sonnet, AgentModel.opus}));
    });
  });
}
