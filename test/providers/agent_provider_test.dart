// agent_provider_test.dart — one test() per AgentProvider variant, per
// dartrix's testing paradigm — a loop here would collapse every variant's
// pass/fail into one result and hide failures after the first.

import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _bedrockFull = {
  'CLAUDE_CODE_USE_BEDROCK': '1',
  'AWS_PROFILE': 'ai-tooling-bedrock-access',
  'AWS_REGION': 'us-east-1',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'anthropic.claude-haiku-inference-profile',
  'ANTHROPIC_DEFAULT_SONNET_MODEL': 'anthropic.claude-sonnet-inference-profile',
  'ANTHROPIC_DEFAULT_OPUS_MODEL': 'anthropic.claude-opus-inference-profile',
};

void main() {
  group('AgentProvider.isSatisfiedBy / missingFrom', () {
    test('apiKey is satisfied by ANTHROPIC_API_KEY alone', () {
      const env = {'ANTHROPIC_API_KEY': 'sk-ant-test'};
      expect(AgentProvider.apiKey.isSatisfiedBy(env), isTrue);
      expect(AgentProvider.apiKey.missingFrom(env), isEmpty);
    });

    test('bedrock requires its full six-var set — application inference profiles need more than the flag + profile', () {
      const partial = {'CLAUDE_CODE_USE_BEDROCK': '1', 'AWS_PROFILE': 'ai-tooling-bedrock-access'};
      expect(AgentProvider.bedrock.isSatisfiedBy(partial), isFalse);
      expect(
        AgentProvider.bedrock.missingFrom(partial),
        equals([
          'AWS_REGION',
          'ANTHROPIC_DEFAULT_HAIKU_MODEL',
          'ANTHROPIC_DEFAULT_SONNET_MODEL',
          'ANTHROPIC_DEFAULT_OPUS_MODEL',
        ]),
      );
      expect(AgentProvider.bedrock.isSatisfiedBy(_bedrockFull), isTrue);
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
      final env = {..._bedrockFull, 'AWS_PROFILE': ''};
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
      final result = AgentProvider.detect(_bedrockFull);
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

  group('AgentProvider.detectEffective', () {
    test('finds a provider configured only in ~/.claude/settings.json, invisible to process env alone', () {
      final io = MemoryFileIO(files: {
        '/fake/settings.json': '{"env": ${_jsonEncode(_bedrockFull)}}',
      });
      final result = AgentProvider.detectEffective(
        processEnv: const {},
        io: io,
        settingsPath: '/fake/settings.json',
      );
      expect(result, equals(AgentProvider.bedrock));
      // The exact bug this closes: detect() alone sees nothing here.
      expect(AgentProvider.detect(const {}), isNull);
    });

    test('process env wins over settings.json on conflicting keys', () {
      final io = MemoryFileIO(files: {
        '/fake/settings.json': '{"env": {"ANTHROPIC_API_KEY": "from-settings"}}',
      });
      final result = AgentProvider.detectEffective(
        processEnv: const {'ANTHROPIC_API_KEY': ''},
        io: io,
        settingsPath: '/fake/settings.json',
      );
      // Process env's empty value should NOT be silently overridden —
      // an explicit empty override in the live process wins.
      expect(result, isNull);
    });

    test('falls back to process-env-only behavior when settings.json has nothing usable', () {
      final io = MemoryFileIO();
      final result = AgentProvider.detectEffective(
        processEnv: const {'ANTHROPIC_API_KEY': 'sk-ant-test'},
        io: io,
        settingsPath: '/fake/missing.json',
      );
      expect(result, equals(AgentProvider.apiKey));
    });
  });
}

String _jsonEncode(Map<String, String> m) =>
    '{${m.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}';
