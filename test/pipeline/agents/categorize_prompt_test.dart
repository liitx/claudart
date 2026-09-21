// categorize_prompt_test.dart — verifies the categorize system
// prompt stays structurally tied to the enum taxonomy.
//
// Test surface iterates `CategorizeTag.values` and each tag's
// `.allowedValues`. Adding a CategorizeTag variant breaks the
// `allowedValues` switch in production; adding an enum variant on
// any axis (AgentCategory, IntentClass, ComplexityTier, AgentModel)
// shows up here automatically via .values iteration.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agents/categorization.dart';
import 'package:test/test.dart';

void main() {
  test('taxonomy cell count matches the documented 6 × 5 × 3 = 90', () {
    final cells = AgentCategory.values.length *
        IntentClass.values.length *
        ComplexityTier.values.length;
    expect(cells, equals(90));
  });

  // ── allowedValues per tag is sourced from the right axis enum ─────────────

  group('CategorizeTag.allowedValues mirrors the target enum', () {
    test('category → AgentCategory.values', () {
      expect(
        CategorizeTag.category.allowedValues,
        equals([for (final v in AgentCategory.values) v.name]),
      );
    });

    test('intent → IntentClass.values', () {
      expect(
        CategorizeTag.intent.allowedValues,
        equals([for (final v in IntentClass.values) v.name]),
      );
    });

    test('complexity → ComplexityTier.values', () {
      expect(
        CategorizeTag.complexity.allowedValues,
        equals([for (final v in ComplexityTier.values) v.name]),
      );
    });

    test('model → AgentModel.values', () {
      expect(
        CategorizeTag.model.allowedValues,
        equals([for (final v in AgentModel.values) v.name]),
      );
    });
  });

  // ── allowedValues invariants ──────────────────────────────────────────────

  group('CategorizeTag.allowedValues invariants', () {
    for (final tag in CategorizeTag.values) {
      test('${tag.name} declares at least one allowed value', () {
        expect(tag.allowedValues, isNotEmpty);
      });

      test('${tag.name} allowed values are unique', () {
        expect(
          tag.allowedValues.toSet().length,
          equals(tag.allowedValues.length),
        );
      });

      test('${tag.name} allowed values are non-empty strings', () {
        for (final value in tag.allowedValues) {
          expect(value, isNotEmpty);
        }
      });
    }
  });

  // ── buildCategorizePrompt embeds every tag + every allowed value ──────────

  group('buildCategorizePrompt is derived from the enum taxonomy', () {
    final prompt = buildCategorizePrompt();

    for (final tag in CategorizeTag.values) {
      test('contains ${tag.wireTag}\'s wire-format name', () {
        expect(
          prompt,
          contains('<${tag.wireTag}>'),
          reason: 'missing tag <${tag.wireTag}> in prompt',
        );
      });
    }

    for (final tag in CategorizeTag.values) {
      for (final value in tag.allowedValues) {
        test('contains ${tag.wireTag} allowed value "$value"', () {
          expect(
            prompt,
            contains(value),
            reason:
                '${tag.wireTag} value "$value" missing from prompt — '
                'prompt/parser would drift if LLM emitted it',
          );
        });
      }
    }

    test('is non-empty + carries the schema instruction', () {
      expect(prompt, isNotEmpty);
      // Documents the "no prose" expectation lives in the prompt.
      // Doesn't bake the exact wording (would be a bare-string test);
      // checks the structural claim only.
      expect(prompt.contains('only') || prompt.contains('Output'), isTrue);
      expect(prompt, contains('XML'));
    });

    for (final tag in CategorizeTag.values) {
      test('${tag.wireTag} has a matching open + close in the schema', () {
        // Prevents the LLM mirroring a half-tag schema (`<TAG>:` with no
        // `</TAG>`). The parser requires the closing tag; the prompt
        // must demonstrate it.
        expect(prompt, contains('<${tag.wireTag}>'));
        expect(
          prompt,
          contains('</${tag.wireTag}>'),
          reason: 'closing </${tag.wireTag}> missing from schema',
        );
      });
    }

    test('tag count in the prompt tracks CategorizeTag.values.length', () {
      // The user-facing instruction "Output only the N XML tags" must
      // match the actual variant count so adding a CategorizeTag
      // variant updates the prompt automatically (the audit's
      // hardcoded-"four" concern).
      expect(
        prompt,
        contains('${CategorizeTag.values.length} XML tags'),
        reason:
            'prompt should reference ${CategorizeTag.values.length} '
            'tags, derived from CategorizeTag.values.length',
      );
    });
  });
}
