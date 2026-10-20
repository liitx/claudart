// model_for_categorize_output_test.dart — verifies the parser that
// turns categorize step output into a routed AgentModel.
//
// The full τ matrix (routeModel) is already covered by
// categorization_test.dart. This file exercises the parser layer:
// well-formed input routes correctly, missing/malformed input
// degrades to the fallback per the audit constraint.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agents/categorization.dart';
import 'package:test/test.dart';

const _fallback = AgentModel.sonnet;

String _buildOutput({
  required String category,
  required String intent,
  required String complexity,
}) =>
    '<${CategorizeTag.category.wireTag}>$category</${CategorizeTag.category.wireTag}>\n'
    '<${CategorizeTag.intent.wireTag}>$intent</${CategorizeTag.intent.wireTag}>\n'
    '<${CategorizeTag.complexity.wireTag}>$complexity</${CategorizeTag.complexity.wireTag}>\n';

void main() {
  group('modelForCategorizeOutput — happy path routes via routeModel', () {
    // Spot-checks against the τ matrix declared in routeModel.
    // Adding a new rule to routeModel without adding a row here is
    // intentionally permitted (the matrix test in categorization_test
    // is the authoritative coverage); this is for anchor cases the
    // audit specifically relies on.

    // The fallback is opus here, so a result of sonnet can only come from
    // parsing the tags: it proves the route, not the fallback.
    test('atomic explore → sonnet, never haiku (haiku does not reason)', () {
      final raw = _buildOutput(
        category: AgentCategory.feature.name,
        intent: IntentClass.explore.name,
        complexity: ComplexityTier.atomic.name,
      );
      expect(
        modelForCategorizeOutput(raw, fallback: AgentModel.opus),
        equals(AgentModel.sonnet),
      );
    });

    test('systemic explore → opus (max capability)', () {
      final raw = _buildOutput(
        category: AgentCategory.research.name,
        intent: IntentClass.explore.name,
        complexity: ComplexityTier.systemic.name,
      );
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.opus),
      );
    });

    test('atomic implement → sonnet (balanced reasoning)', () {
      final raw = _buildOutput(
        category: AgentCategory.feature.name,
        intent: IntentClass.implement.name,
        complexity: ComplexityTier.atomic.name,
      );
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.sonnet),
      );
    });
  });

  group(
      'modelForCategorizeOutput — degrades to fallback on ambiguity '
      '(reasoner constraint)', () {
    test('empty input returns fallback', () {
      expect(
        modelForCategorizeOutput('', fallback: _fallback),
        equals(_fallback),
      );
    });

    test('missing CATEGORY tag returns fallback', () {
      final raw =
          '<${CategorizeTag.intent.wireTag}>${IntentClass.explore.name}'
          '</${CategorizeTag.intent.wireTag}>\n'
          '<${CategorizeTag.complexity.wireTag}>${ComplexityTier.atomic.name}'
          '</${CategorizeTag.complexity.wireTag}>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(_fallback),
      );
    });

    test('missing INTENT tag returns fallback', () {
      final raw =
          '<${CategorizeTag.category.wireTag}>${AgentCategory.feature.name}'
          '</${CategorizeTag.category.wireTag}>\n'
          '<${CategorizeTag.complexity.wireTag}>${ComplexityTier.atomic.name}'
          '</${CategorizeTag.complexity.wireTag}>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(_fallback),
      );
    });

    test('missing COMPLEXITY tag returns fallback', () {
      final raw =
          '<${CategorizeTag.category.wireTag}>${AgentCategory.feature.name}'
          '</${CategorizeTag.category.wireTag}>\n'
          '<${CategorizeTag.intent.wireTag}>${IntentClass.explore.name}'
          '</${CategorizeTag.intent.wireTag}>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(_fallback),
      );
    });

    test('unknown enum variant (typo from LLM) returns fallback', () {
      final raw = _buildOutput(
        category: AgentCategory.feature.name,
        intent: 'spelunk', // not a real IntentClass
        complexity: ComplexityTier.atomic.name,
      );
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(_fallback),
      );
    });

    test('different fallback honored (custom default)', () {
      expect(
        modelForCategorizeOutput('', fallback: AgentModel.opus),
        equals(AgentModel.opus),
      );
    });
  });

  group('modelForCategorizeOutput — tag-NAME case insensitivity', () {
    test('lower-case tag names parse (LLM may not honor upper-case prompt)',
        () {
      const raw =
          '<category>feature</category>\n'
          '<intent>explore</intent>\n'
          '<complexity>systemic</complexity>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.opus),
      );
    });

    test('mixed-case tag names parse', () {
      const raw =
          '<Category>feature</Category>\n'
          '<Intent>explore</Intent>\n'
          '<Complexity>systemic</Complexity>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.opus),
      );
    });
  });

  group('modelForCategorizeOutput — tag-VALUE case insensitivity', () {
    test('mixed-case enum names match (LLM may capitalize)', () {
      final raw =
          '<${CategorizeTag.category.wireTag}>Feature</${CategorizeTag.category.wireTag}>\n'
          '<${CategorizeTag.intent.wireTag}>Explore</${CategorizeTag.intent.wireTag}>\n'
          '<${CategorizeTag.complexity.wireTag}>Systemic</${CategorizeTag.complexity.wireTag}>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.opus),
      );
    });

    test('upper-case enum names match', () {
      final raw =
          '<${CategorizeTag.category.wireTag}>FEATURE</${CategorizeTag.category.wireTag}>\n'
          '<${CategorizeTag.intent.wireTag}>EXPLORE</${CategorizeTag.intent.wireTag}>\n'
          '<${CategorizeTag.complexity.wireTag}>SYSTEMIC</${CategorizeTag.complexity.wireTag}>\n';
      expect(
        modelForCategorizeOutput(raw, fallback: _fallback),
        equals(AgentModel.opus),
      );
    });
  });
}
