// doctor_test.dart — runDoctorChecks' checks, one scenario per test()
// per dartrix's testing paradigm. Uses a fake ProcessRunner keyed by
// "<executable> <args>" rather than mocktail, since optional named params
// (workingDirectory) make mocktail's exact-call matching fragile for a
// first-time consumer of MockProcessRunner.

import 'dart:async';
import 'dart:io';

import 'package:claudart/commands/doctor.dart';
import 'package:claudart/git_utils.dart';
import 'package:claudart/harness/harness_check.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/process_runner.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

/// Thrown by the injected exitFn so tests can assert exit-code behaviour
/// without terminating the process.
class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

typedef _RecordedCall = ({
  String executable,
  List<String> arguments,
  Map<String, String>? environment,
});

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(this.responses, {this.notFound = const {}});

  final Map<String, ProcessResult> responses;

  /// Executables that should behave like a real fresh machine where the
  /// binary genuinely isn't installed: `Process.run` throws
  /// `ProcessException` synchronously, rather than returning a nonzero
  /// exit code.
  final Set<String> notFound;

  /// Every call this runner received, in order — lets a test assert
  /// *what* was passed to a specific subprocess (e.g. the `environment`
  /// an `aws` call actually received), not just the response it got back.
  final List<_RecordedCall> calls = [];

  ProcessResult _resolve(
    String executable,
    List<String> arguments,
    Map<String, String>? environment,
  ) {
    calls.add((executable: executable, arguments: arguments, environment: environment));
    if (notFound.contains(executable)) {
      throw ProcessException(executable, arguments, 'No such file or directory');
    }
    return responses['$executable ${arguments.join(' ')}'] ??
        ProcessResult(0, 127, '', 'command not found');
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async =>
      _resolve(executable, arguments, environment);

  @override
  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      _resolve(executable, arguments, environment);

  @override
  Future<ProcessResult> runKillable(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async =>
      _resolve(executable, arguments, environment);
}

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

/// Builds the exact fake-runner key a `readGitConfig`/`writeGitConfig` call
/// for [key] resolves to — from the same `gitEnvClearExecutable`/
/// `gitEnvClearArgs` the implementation itself uses, not a second,
/// separately-typed copy of the `env -u ...` flags.
String _gitConfigCall(GitConfigKey key) =>
    '$gitEnvClearExecutable ${gitEnvClearArgs.join(' ')} git config ${key.gitKey}';

/// A baseline env with HOME/PATH set so `pathConfiguration` passes by
/// default — individual tests override/add only the keys they care about,
/// matching the pattern every other check already uses.
const _cleanEnv = {'HOME': '/fake/home', 'PATH': '/fake/home/bin:/usr/bin'};

const _bedrockAuthStatus =
    '{"loggedIn": true, "authMethod": "third_party", "apiProvider": "bedrock"}';

Map<String, ProcessResult> _responses({
  bool claudeOnPath = true,
  bool gitIdentitySet = true,
  bool ghAuthed = true,
  String authStatusStdout = '',
  bool awsOnPath = true,
  ProcessResult? awsStsResult,
}) =>
    {
      'which git': _ok(''),
      'which gh': _ok(''),
      'which claude': claudeOnPath ? _ok('') : _fail(),
      'which aws': awsOnPath ? _ok('') : _fail(),
      _gitConfigCall(GitConfigKey.userName): gitIdentitySet ? _ok('Aksana Buster') : _fail(),
      _gitConfigCall(GitConfigKey.userEmail): gitIdentitySet ? _ok('ab@liitx.com') : _fail(),
      'gh auth status': ghAuthed ? _ok('') : _fail(),
      'claude auth status': _ok(authStatusStdout),
      if (awsStsResult != null) 'aws sts get-caller-identity': awsStsResult,
    };

/// A [ProcessRunner] whose `runKillable` genuinely honors [timeout] by
/// waiting it out and then throwing — isolates the
/// `bedrockCredentialsPreflight` check's timeout path realistically (as
/// `RealProcessRunner.runKillable` would behave against a hung `aws`
/// process) without ever hanging the test suite itself, since tests pass
/// a tiny [timeout].
class _HangingProcessRunner implements ProcessRunner {
  const _HangingProcessRunner(this._fallback);
  final ProcessRunner _fallback;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      _fallback.run(executable, arguments, workingDirectory: workingDirectory, environment: environment);

  @override
  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      _fallback.runSync(executable, arguments, workingDirectory: workingDirectory, environment: environment);

  @override
  Future<ProcessResult> runKillable(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    if (executable == 'aws' && arguments.first == 'sts') {
      await Future<void>.delayed(timeout);
      throw TimeoutException('$executable ${arguments.join(' ')} hung', timeout);
    }
    return _fallback.runKillable(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );
  }
}

void main() {
  group('runDoctorChecks — tools', () {
    test('ok when git, gh, and claude are all on PATH', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final tools = outcomes.firstWhere((o) => o.id == HarnessCheckId.tools);
      expect(tools.result, equals(HarnessCheckResult.ok));
      expect(tools.detail, contains('claude'));
    });

    test('fails and names the missing tool when claude is not on PATH', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(claudeOnPath: false)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final tools = outcomes.firstWhere((o) => o.id == HarnessCheckId.tools);
      expect(tools.result, equals(HarnessCheckResult.fail));
      expect(tools.detail, contains('claude'));
    });
  });

  group('runDoctorChecks — a genuinely missing tool does not crash the harness', () {
    test('gh missing entirely: ghAuth fails instead of throwing ProcessException', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(), notFound: const {'gh'}),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final auth = outcomes.firstWhere((o) => o.id == HarnessCheckId.ghAuth);
      expect(auth.result, equals(HarnessCheckResult.fail));
    });

    test('git missing entirely: gitIdentity fails instead of throwing ProcessException', () async {
      // Every git call now goes through `env -u ... git ...` — `env` itself
      // genuinely missing isn't the realistic failure mode (it's a
      // near-universal tool); git missing means `env` runs fine but fails
      // to exec `git`, landing on the fake runner's own "no response
      // configured" fallback (exit 127), not a thrown ProcessException.
      final responses = _responses()
        ..remove(_gitConfigCall(GitConfigKey.userName))
        ..remove(_gitConfigCall(GitConfigKey.userEmail));
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(responses),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final identity = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitIdentity);
      expect(identity.result, equals(HarnessCheckResult.fail));
    });

    test('which itself missing: tools fails instead of throwing ProcessException', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(), notFound: const {'which'}),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final tools = outcomes.firstWhere((o) => o.id == HarnessCheckId.tools);
      expect(tools.result, equals(HarnessCheckResult.fail));
    });
  });

  group('runDoctorChecks — git identity', () {
    test('ok when user.name and user.email are both set', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final identity = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitIdentity);
      expect(identity.result, equals(HarnessCheckResult.ok));
      expect(identity.detail, equals('Aksana Buster <ab@liitx.com>'));
    });

    test('fails when git config has no identity set', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(gitIdentitySet: false)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final identity = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitIdentity);
      expect(identity.result, equals(HarnessCheckResult.fail));
    });
  });

  group('runDoctorChecks — gh auth', () {
    test('ok when gh auth status succeeds', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final auth = outcomes.firstWhere((o) => o.id == HarnessCheckId.ghAuth);
      expect(auth.result, equals(HarnessCheckResult.ok));
    });

    test('fails when gh auth status exits non-zero', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(ghAuthed: false)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final auth = outcomes.firstWhere((o) => o.id == HarnessCheckId.ghAuth);
      expect(auth.result, equals(HarnessCheckResult.fail));
    });
  });

  group('runDoctorChecks — provider env', () {
    test('ok and names the provider when one is configured', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: {..._cleanEnv, 'ANTHROPIC_API_KEY': 'sk-ant-test'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final provider = outcomes.firstWhere((o) => o.id == HarnessCheckId.providerEnv);
      expect(provider.result, equals(HarnessCheckResult.ok));
      expect(provider.detail, contains('apiKey'));
    });

    test('skips — not a failure — when no provider env vars are set', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final provider = outcomes.firstWhere((o) => o.id == HarnessCheckId.providerEnv);
      expect(provider.result, equals(HarnessCheckResult.skip));
    });

    test('ok when a provider is configured only in ~/.claude/settings.json, not process env', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {
          '/fake/settings.json': '{"env": {"ANTHROPIC_API_KEY": "sk-ant-test"}}',
        }),
        claudeSettingsPath: '/fake/settings.json',
      );
      final provider = outcomes.firstWhere((o) => o.id == HarnessCheckId.providerEnv);
      expect(provider.result, equals(HarnessCheckResult.ok));
      expect(provider.detail, contains('apiKey'));
    });
  });

  group('runDoctorChecks — workspace root', () {
    test('ok when CLAUDART_WORKSPACE is set, exists, and the fallback has no registry', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: {..._cleanEnv, 'CLAUDART_WORKSPACE': '/fake/workspace-root'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(dirs: {'/fake/workspace-root'}),
      );
      final root = outcomes.firstWhere((o) => o.id == HarnessCheckId.workspaceRoot);
      expect(root.result, equals(HarnessCheckResult.ok));
      expect(root.detail, contains('/fake/workspace-root'));
    });

    test('skips — not a failure — when CLAUDART_WORKSPACE is unset', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final root = outcomes.firstWhere((o) => o.id == HarnessCheckId.workspaceRoot);
      expect(root.result, equals(HarnessCheckResult.skip));
    });

    test('fails when CLAUDART_WORKSPACE points at a directory that does not exist', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: {..._cleanEnv, 'CLAUDART_WORKSPACE': '/fake/does-not-exist'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final root = outcomes.firstWhere((o) => o.id == HarnessCheckId.workspaceRoot);
      expect(root.result, equals(HarnessCheckResult.fail));
      expect(root.detail, contains('does not exist'));
    });

    test('fails — the real split-brain — when the override is valid but ~/.claudart also has a registry', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: {..._cleanEnv, 'CLAUDART_WORKSPACE': '/fake/workspace-root'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(
          dirs: {'/fake/workspace-root'},
          files: {'/fake/home/.claudart/registry.json': '{"workspaces": []}'},
        ),
      );
      final root = outcomes.firstWhere((o) => o.id == HarnessCheckId.workspaceRoot);
      expect(root.result, equals(HarnessCheckResult.fail));
      expect(root.detail, contains('split-brain'));
    });
  });

  group('runDoctorChecks — registry health', () {
    test('skips when the registry file does not exist yet', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.skip));
    });

    test('skips when the registry file exists but is empty', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {registryPath: ''}),
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.skip));
    });

    test('skips when the registry parses but has no entries', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {registryPath: '{"workspaces": []}'}),
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.skip));
    });

    test('fails — distinct from "nothing linked" — when the registry file is corrupt', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {registryPath: '{not valid json'}),
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.fail));
      expect(health.detail, contains('failed to parse'));
    });

    test('ok when every registered projectRoot still exists on disk', () async {
      // Registry.load() always resolves via the real registryPath getter
      // (lib/paths.dart) — unaffected by the `env` map passed to
      // runDoctorChecks — so the fixture has to live at that real,
      // machine-dependent path, not an arbitrary fake one.
      final io = MemoryFileIO(
        dirs: {'/fake/projects/a'},
        files: {
          registryPath: '''
{"workspaces": [{"name": "a", "projectRoot": "/fake/projects/a", "workspacePath": "/fake/workspace-root/a", "createdAt": "", "lastSession": ""}]}
''',
        },
      );
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: io,
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.ok));
      // Singular "1 entry", not "1 entries" — caught during cross-machine
      // testing of this PR.
      expect(health.detail, contains('1 entry,'));
    });

    test('fails and names the stale entry when a projectRoot no longer exists', () async {
      final io = MemoryFileIO(
        files: {
          registryPath: '''
{"workspaces": [{"name": "gone", "projectRoot": "/fake/projects/gone", "workspacePath": "/fake/workspace-root/gone", "createdAt": "", "lastSession": ""}]}
''',
        },
      );
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: {..._cleanEnv, 'CLAUDART_WORKSPACE': '/fake/workspace-root'},
        projectRoot: '/fake/repo',
        io: io,
      );
      final health = outcomes.firstWhere((o) => o.id == HarnessCheckId.registryHealth);
      expect(health.result, equals(HarnessCheckResult.fail));
      expect(health.detail, contains('gone'));
    });
  });

  group('runDoctorChecks — path configuration', () {
    test('ok when ~/bin is on PATH', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final pathCheck = outcomes.firstWhere((o) => o.id == HarnessCheckId.pathConfiguration);
      expect(pathCheck.result, equals(HarnessCheckResult.ok));
    });

    test('fails when ~/bin is not on PATH', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: const {'HOME': '/fake/home', 'PATH': '/usr/bin:/usr/local/bin'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final pathCheck = outcomes.firstWhere((o) => o.id == HarnessCheckId.pathConfiguration);
      expect(pathCheck.result, equals(HarnessCheckResult.fail));
    });
  });

  group('runDoctorChecks — bedrock metadata guard', () {
    test('skips — not a failure — when Bedrock is not the active provider', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final guard = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockMetadataDisabled);
      expect(guard.result, equals(HarnessCheckResult.skip));
    });

    test('fails when Bedrock is active and AWS_EC2_METADATA_DISABLED is not set', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final guard = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockMetadataDisabled);
      expect(guard.result, equals(HarnessCheckResult.fail));
      expect(guard.detail, contains('AWS_EC2_METADATA_DISABLED'));
    });

    test('ok when Bedrock is active and AWS_EC2_METADATA_DISABLED=true', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus)),
        env: {..._cleanEnv, 'AWS_EC2_METADATA_DISABLED': 'true'},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final guard = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockMetadataDisabled);
      expect(guard.result, equals(HarnessCheckResult.ok));
    });
  });

  group('runDoctorChecks — bedrock credentials preflight', () {
    test('skips — not a failure — when Bedrock is not the active provider', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final preflight = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockCredentialsPreflight);
      expect(preflight.result, equals(HarnessCheckResult.skip));
    });

    test('skips when Bedrock is active but the aws CLI is not installed', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus, awsOnPath: false)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final preflight = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockCredentialsPreflight);
      expect(preflight.result, equals(HarnessCheckResult.skip));
      expect(preflight.detail, contains('aws CLI not found'));
    });

    test('ok when aws sts get-caller-identity succeeds — never prints the resolved identity', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(
          authStatusStdout: _bedrockAuthStatus,
          awsStsResult: _ok('{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'),
        )),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final preflight = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockCredentialsPreflight);
      expect(preflight.result, equals(HarnessCheckResult.ok));
      expect(preflight.detail, isNot(contains('arn:aws')));
      expect(preflight.detail, isNot(contains('123456789012')));
    });

    test('fails when aws sts get-caller-identity exits non-zero', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus, awsStsResult: _fail())),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final preflight = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockCredentialsPreflight);
      expect(preflight.result, equals(HarnessCheckResult.fail));
    });

    test('fails — does not hang the suite — when the call exceeds the bounded timeout', () async {
      final outcomes = await runDoctorChecks(
        runner: _HangingProcessRunner(_FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus))),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
        bedrockPreflightTimeout: const Duration(milliseconds: 20),
      );
      final preflight = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockCredentialsPreflight);
      expect(preflight.result, equals(HarnessCheckResult.fail));
      expect(preflight.detail, contains('did not respond within'));
    });
  });

  group('runDoctorChecks — bedrock checks read settings.json env, not just process env', () {
    // Confirmed on a real Bedrock-only machine: the flag and AWS_PROFILE
    // can live ONLY in ~/.claude/settings.json's own `env` block, the same
    // place `claude` itself reads Bedrock config from — a plain Terminal
    // with nothing exported false-[FAIL]ed both checks before this fix,
    // the same blind spot `providerEnv` already had before `detectEffective`.
    const settingsPath = '/fake/settings.json';
    const settingsJson = '{"env": {'
        '"CLAUDE_CODE_USE_BEDROCK": "1", '
        '"AWS_PROFILE": "ai-tooling-bedrock-access", '
        '"AWS_EC2_METADATA_DISABLED": "true"'
        '}}';

    test('bedrockMetadataDisabled is ok when the flag lives only in settings.json', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(authStatusStdout: _bedrockAuthStatus)),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {settingsPath: settingsJson}),
        claudeSettingsPath: settingsPath,
      );
      final guard = outcomes.firstWhere((o) => o.id == HarnessCheckId.bedrockMetadataDisabled);
      expect(guard.result, equals(HarnessCheckResult.ok));
    });

    test('bedrockCredentialsPreflight passes AWS_PROFILE from settings.json to the aws subprocess', () async {
      final runner = _FakeProcessRunner(_responses(
        authStatusStdout: _bedrockAuthStatus,
        awsStsResult: _ok('{}'),
      ));
      await runDoctorChecks(
        runner: runner,
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(files: {settingsPath: settingsJson}),
        claudeSettingsPath: settingsPath,
      );
      final awsCall = runner.calls.firstWhere(
        (c) => c.executable == 'aws' && c.arguments.contains('sts'),
      );
      expect(awsCall.environment, isNotNull);
      expect(awsCall.environment!['AWS_PROFILE'], equals('ai-tooling-bedrock-access'));
    });
  });

  group('runDoctorChecks — git hooks configured', () {
    test('skips — not a failure — when the project has no .githooks/', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final hooks = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitHooksConfigured);
      expect(hooks.result, equals(HarnessCheckResult.skip));
    });

    test('ok when .githooks/ exists and core.hooksPath points at it', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner({
          ..._responses(),
          _gitConfigCall(GitConfigKey.hooksPath): _ok('.githooks'),
        }),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(dirs: {'/fake/repo/.githooks'}),
      );
      final hooks = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitHooksConfigured);
      expect(hooks.result, equals(HarnessCheckResult.ok));
    });

    test('fails when .githooks/ exists but core.hooksPath is not set to it', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner({
          ..._responses(),
          _gitConfigCall(GitConfigKey.hooksPath): _fail(),
        }),
        env: _cleanEnv,
        projectRoot: '/fake/repo',
        io: MemoryFileIO(dirs: {'/fake/repo/.githooks'}),
      );
      final hooks = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitHooksConfigured);
      expect(hooks.result, equals(HarnessCheckResult.fail));
    });
  });

  group('runDoctor exit code', () {
    test('exits 0 when every check is ok or skip', () async {
      _ExitException? caught;
      try {
        await runDoctor(
          runner: _FakeProcessRunner(_responses()),
          env: _cleanEnv,
          projectRootOverride: '/fake/repo',
          io: MemoryFileIO(),
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(0));
    });

    test('exits 1 when any check fails', () async {
      _ExitException? caught;
      try {
        await runDoctor(
          runner: _FakeProcessRunner(_responses(ghAuthed: false)),
          env: _cleanEnv,
          projectRootOverride: '/fake/repo',
          io: MemoryFileIO(),
          exitFn: _throwExit,
        );
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(1));
    });
  });
}
