import 'package:claudart/pipeline/agent_model.dart';
import 'package:test/test.dart';

// claudart owns AgentModel, so claudart tests it. These literal tables are the
// contract; consumers (zedup) use the values and do not re-assert them.

typedef _Spec = ({
  String alias,
  String slug,
  String shortName,
  int contextWindow,
  int maxOutputTokens,
  ModelTier tier,
});

const _specs = <AgentModel, _Spec>{
  AgentModel.haiku: (
    alias: 'haiku',
    slug: 'claude-haiku-4-5-20251001',
    shortName: 'haiku-4.5',
    contextWindow: 200000,
    maxOutputTokens: 8192,
    tier: ModelTier.fast,
  ),
  AgentModel.sonnet: (
    alias: 'sonnet',
    slug: 'claude-sonnet-5-5',
    shortName: 'sonnet-5',
    contextWindow: 200000,
    maxOutputTokens: 16000,
    tier: ModelTier.balanced,
  ),
  AgentModel.opus: (
    alias: 'opus',
    slug: 'claude-opus-5-5',
    shortName: 'opus-5.5',
    contextWindow: 200000,
    maxOutputTokens: 32000,
    tier: ModelTier.capable,
  ),
  AgentModel.fable: (
    alias: 'fable',
    slug: 'claude-fable-5-1',
    shortName: 'fable-5.1',
    contextWindow: 200000,
    maxOutputTokens: 32000,
    tier: ModelTier.capable,
  ),
};

void main() {
  test('the table covers every variant', () {
    expect(_specs.keys.toSet(), AgentModel.values.toSet());
  });

  group('AgentModel fields', () {
    for (final entry in _specs.entries) {
      final model = entry.key;
      final spec = entry.value;
      test('${model.name}: alias, slug, shortName, limits and tier', () {
        expect(model.alias, spec.alias);
        expect(model.slug, spec.slug);
        expect(model.shortName, spec.shortName);
        expect(model.contextWindow, spec.contextWindow);
        expect(model.maxOutputTokens, spec.maxOutputTokens);
        expect(model.tier, spec.tier);
      });
    }
  });

  group('the one-model-per-task predicates', () {
    // Identity-based, not tier-derived: fable shares opus's tier but is not
    // the explore choice.
    const lookup = {AgentModel.haiku};
    const analysis = {AgentModel.sonnet};
    const explore = {AgentModel.opus};

    for (final model in AgentModel.values) {
      test('${model.name}: bestForLookup / Analysis / Explore', () {
        expect(model.bestForLookup, lookup.contains(model));
        expect(model.bestForAnalysis, analysis.contains(model));
        expect(model.bestForExplore, explore.contains(model));
      });
    }

    test('exactly one model is best for each task', () {
      expect(AgentModel.values.where((m) => m.bestForLookup), hasLength(1));
      expect(AgentModel.values.where((m) => m.bestForAnalysis), hasLength(1));
      expect(AgentModel.values.where((m) => m.bestForExplore), hasLength(1));
    });
  });

  group('parsing', () {
    for (final entry in _specs.entries) {
      test('${entry.key.name}: fromAlias and fromSlug round-trip', () {
        expect(AgentModel.fromAlias(entry.value.alias), entry.key);
        expect(AgentModel.fromSlug(entry.value.slug), entry.key);
      });
    }

    test('an unknown alias or slug is null (forward-compatible)', () {
      expect(AgentModel.fromAlias('gpt'), isNull);
      expect(AgentModel.fromAlias(''), isNull);
      expect(AgentModel.fromSlug('claude-unknown'), isNull);
    });

    test('an alias is not a slug and a slug is not an alias', () {
      expect(AgentModel.fromSlug('haiku'), isNull);
      expect(AgentModel.fromAlias('claude-haiku-4-5-20251001'), isNull);
    });
  });

  group('ModelTier.label', () {
    const labels = {
      ModelTier.fast: 'fast',
      ModelTier.balanced: 'balanced',
      ModelTier.capable: 'capable',
    };

    test('the table covers every tier', () {
      expect(labels.keys.toSet(), ModelTier.values.toSet());
    });

    for (final entry in labels.entries) {
      test('${entry.key.name}: ${entry.value}', () {
        expect(entry.key.label, entry.value);
      });
    }
  });
}
