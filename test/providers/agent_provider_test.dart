// agent_provider_test.dart — one test() per AgentProvider variant, per
// dartrix's testing paradigm — a loop here would collapse every variant's
// pass/fail into one result and hide failures after the first.

import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

void main() {
  group('AgentProvider.isSatisfiedBy / missingFrom', () {
    test('apiKey is satisfied by ANTHROPIC_API_KEY alone', () {
      const env = {'ANTHROPIC_API_KEY': 'sk-ant-test'};
      expect(AgentProvider.apiKey.isSatisfiedBy(env), isTrue);
      expect(AgentProvider.apiKey.missingFrom(env), isEmpty);
    });

    test('bedrock requires both CLAUDE_CODE_USE_BEDROCK and AWS_PROFILE', () {
      const partial = {'CLAUDE_CODE_USE_BEDROCK': '1'};
      expect(AgentProvider.bedrock.isSatisfiedBy(partial), isFalse);
      expect(AgentProvider.bedrock.missingFrom(partial), equals(['AWS_PROFILE']));

      const full = {
        'CLAUDE_CODE_USE_BEDROCK': '1',
        'AWS_PROFILE': 'ai-tooling-bedrock-access',
      };
      expect(AgentProvider.bedrock.isSatisfiedBy(full), isTrue);
    });

    test('openRouter is satisfied by OPENROUTER_API_KEY alone', () {
      const env = {'OPENROUTER_API_KEY': 'or-test'};
      expect(AgentProvider.openRouter.isSatisfiedBy(env), isTrue);
      expect(AgentProvider.openRouter.missingFrom(env), isEmpty);
    });
  });

  group('AgentProvider.isSatisfiedBy treats empty values as missing', () {
    test('apiKey', () {
      const env = {'ANTHROPIC_API_KEY': ''};
      expect(AgentProvider.apiKey.isSatisfiedBy(env), isFalse);
    });

    test('bedrock', () {
      const env = {'CLAUDE_CODE_USE_BEDROCK': '1', 'AWS_PROFILE': ''};
      expect(AgentProvider.bedrock.isSatisfiedBy(env), isFalse);
    });

    test('openRouter', () {
      const env = {'OPENROUTER_API_KEY': ''};
      expect(AgentProvider.openRouter.isSatisfiedBy(env), isFalse);
    });
  });

  group('AgentProvider.detect', () {
    test('returns null when no provider is configured', () {
      expect(AgentProvider.detect(const {}), isNull);
    });

    test('detects apiKey from ANTHROPIC_API_KEY', () {
      final result = AgentProvider.detect(const {'ANTHROPIC_API_KEY': 'sk-ant-test'});
      expect(result, equals(AgentProvider.apiKey));
    });

    test('detects bedrock from its full var set', () {
      final result = AgentProvider.detect(const {
        'CLAUDE_CODE_USE_BEDROCK': '1',
        'AWS_PROFILE': 'ai-tooling-bedrock-access',
      });
      expect(result, equals(AgentProvider.bedrock));
    });

    test('detects openRouter from OPENROUTER_API_KEY', () {
      final result = AgentProvider.detect(const {'OPENROUTER_API_KEY': 'or-test'});
      expect(result, equals(AgentProvider.openRouter));
    });

    test('explicit override wins even when a different provider is also configured', () {
      final result = AgentProvider.detect(
        const {'ANTHROPIC_API_KEY': 'sk-ant-test'},
        explicit: AgentProvider.bedrock,
      );
      expect(result, equals(AgentProvider.bedrock));
    });

    test('first-declared provider wins when more than one is satisfied with no explicit override', () {
      final result = AgentProvider.detect(const {
        'ANTHROPIC_API_KEY': 'sk-ant-test',
        'OPENROUTER_API_KEY': 'or-test',
      });
      expect(result, equals(AgentProvider.apiKey));
    });
  });
}
