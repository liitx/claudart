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

  group('AgentProvider.detectFromAuthStatusJson — exact fixtures from OAUTH-BEDROCK-FINAL-REPORT.md', () {
    test('nothing configured (none/firstParty, exits 1) -> null', () {
      const stdout = '{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), isNull);
    });

    test('Bedrock active (third_party/bedrock) -> bedrock', () {
      const stdout = '{"loggedIn": true, "authMethod": "third_party", "apiProvider": "bedrock"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), equals(AgentProvider.bedrock));
    });

    test('ANTHROPIC_API_KEY set (api_key/firstParty) -> apiKey', () {
      const stdout = '{"loggedIn": true, "authMethod": "api_key", "apiProvider": "firstParty"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), equals(AgentProvider.apiKey));
    });

    test('CLAUDE_CODE_OAUTH_TOKEN set (oauth_token/firstParty) -> claudeAi', () {
      const stdout = '{"loggedIn": true, "authMethod": "oauth_token", "apiProvider": "firstParty"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), equals(AgentProvider.claudeAi));
    });

    // The exact reading from the owner's machine (team subscription): the CLI
    // runs on this login, so it must count as a provider.
    test('claude.ai browser login (claude.ai/firstParty) -> claudeAi', () {
      const stdout = '{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty", "subscriptionType": "team"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), equals(AgentProvider.claudeAi));
    });

    test('a claude.ai method that is not logged in -> null', () {
      const stdout = '{"loggedIn": false, "authMethod": "claude.ai", "apiProvider": "firstParty"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), isNull);
    });

    test('Bedrock + API key both set -> bedrock wins, matching measured precedence', () {
      const stdout = '{"loggedIn": true, "authMethod": "third_party", "apiProvider": "bedrock", "apiKeySource": "ANTHROPIC_API_KEY"}';
      expect(AgentProvider.detectFromAuthStatusJson(stdout), equals(AgentProvider.bedrock));
    });

    test('malformed JSON -> null, not a thrown exception', () {
      expect(AgentProvider.detectFromAuthStatusJson('not json'), isNull);
      expect(AgentProvider.detectFromAuthStatusJson(''), isNull);
    });
  });

  _loginGroups();
}


// A login has no env vars, so it must never be found by looking at the
// environment (an empty requirement would match every environment).
void _loginGroups() {
  group('AgentProvider.isEnvConfigured', () {
    // Independent literals: can the environment alone establish it?
    const envConfigured = {
      AgentProvider.apiKey: true,
      AgentProvider.bedrock: true,
      AgentProvider.openRouter: true,
      AgentProvider.claudeAi: false,
    };
    for (final provider in AgentProvider.values) {
      test('${provider.name} -> ${envConfigured[provider]}', () {
        expect(provider.isEnvConfigured, envConfigured[provider]);
      });
    }

    test('every provider has a pinned answer', () {
      expect(envConfigured.keys.toSet(), AgentProvider.values.toSet());
    });

    test('an empty environment still detects nothing (the login does not '
        'match vacuously)', () {
      expect(AgentProvider.detect(const {}), isNull);
    });
  });

  group('AgentProvider.isActiveIn: every provider against every reading', () {
    ClaudeAuthStatus reading(bool loggedIn, String? method, String? api) =>
        (loggedIn: loggedIn, authMethod: method, apiProvider: api);

    // (name, reading) -> the providers that say they are active in it.
    final readings = <String, (ClaudeAuthStatus, Set<AgentProvider>)>{
      'nothing configured': (reading(false, 'none', 'firstParty'), {}),
      'bedrock': (
        reading(true, 'third_party', 'bedrock'),
        {AgentProvider.bedrock},
      ),
      'api key': (
        reading(true, 'api_key', 'firstParty'),
        {AgentProvider.apiKey},
      ),
      'browser login': (
        reading(true, 'claude.ai', 'firstParty'),
        {AgentProvider.claudeAi},
      ),
      'oauth token': (
        reading(true, 'oauth_token', 'firstParty'),
        {AgentProvider.claudeAi},
      ),
      'browser login, not logged in': (
        reading(false, 'claude.ai', 'firstParty'),
        {},
      ),
      'unknown method': (reading(true, 'something_new', 'firstParty'), {}),
    };

    readings.forEach((name, expected) {
      final (status, active) = expected;
      for (final provider in AgentProvider.values) {
        test('$name: ${provider.name} is ${active.contains(provider)}', () {
          expect(provider.isActiveIn(status), active.contains(provider));
        });
      }
    });

    test('openRouter is never read from a login', () {
      expect(
        AgentProvider.openRouter.isActiveIn(reading(true, 'api_key', 'x')),
        isFalse,
      );
    });
  });

  group('parseClaudeAuthStatus', () {
    test('reads the three fields', () {
      final status = parseClaudeAuthStatus(
        '{"loggedIn": true, "authMethod": "claude.ai", '
        '"apiProvider": "firstParty"}',
      );
      expect(status, (
        loggedIn: true,
        authMethod: 'claude.ai',
        apiProvider: 'firstParty',
      ));
    });

    test('missing fields read as not logged in, with no method', () {
      expect(parseClaudeAuthStatus('{}'), (
        loggedIn: false,
        authMethod: null,
        apiProvider: null,
      ));
    });

    const unreadable = {
      'not json': 'nope',
      'a list': '[1]',
      'empty': '',
      'fields of the wrong type': '{"authMethod": 3}',
    };
    unreadable.forEach((name, text) {
      test('$name -> null, not a crash', () {
        expect(parseClaudeAuthStatus(text), isNull);
      });
    });

    test('ClaudeAuthField names are the keys of the JSON', () {
      expect(
        ClaudeAuthField.values.map((f) => f.name),
        ['loggedIn', 'authMethod', 'apiProvider'],
      );
    });
  });

  group('AgentProvider.resolve: the environment first, then the login', () {
    const browserLogin =
        '{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}';
    const nothing = '{"loggedIn": false, "authMethod": "none"}';

    Future<AgentProvider?> resolve(
      Map<String, String> env,
      String authStatus,
    ) =>
        AgentProvider.resolve(
          processEnv: env,
          io: MemoryFileIO(),
          settingsPath: '/none/settings.json',
          authStatusStdout: () async => authStatus,
        );

    test('a key in the environment wins over a login', () async {
      expect(
        await resolve(const {'ANTHROPIC_API_KEY': 'sk-ant-test'}, browserLogin),
        AgentProvider.apiKey,
      );
    });

    test('no environment, a browser login: claudeAi (the blocker)', () async {
      expect(await resolve(const {}, browserLogin), AgentProvider.claudeAi);
    });

    test('no environment and not logged in: null', () async {
      expect(await resolve(const {}, nothing), isNull);
    });

    test('no environment and unreadable status output: null', () async {
      expect(await resolve(const {}, 'claude: command not found'), isNull);
    });

    test('an explicit provider wins outright', () async {
      expect(
        await AgentProvider.resolve(
          processEnv: const {},
          io: MemoryFileIO(),
          settingsPath: '/none/settings.json',
          explicit: AgentProvider.bedrock,
          authStatusStdout: () async => browserLogin,
        ),
        AgentProvider.bedrock,
      );
    });
  });
}

String _jsonEncode(Map<String, String> m) =>
    '{${m.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}';
