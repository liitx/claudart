// doctor_test.dart — runDoctorChecks' four checks, one scenario per test()
// per dartrix's testing paradigm. Uses a fake ProcessRunner keyed by
// "<executable> <args>" rather than mocktail, since optional named params
// (workingDirectory) make mocktail's exact-call matching fragile for a
// first-time consumer of MockProcessRunner.

import 'dart:io';

import 'package:claudart/commands/doctor.dart';
import 'package:claudart/harness/harness_check.dart';
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

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(this.responses, {this.notFound = const {}});

  final Map<String, ProcessResult> responses;

  /// Executables that should behave like a real fresh machine where the
  /// binary genuinely isn't installed: `Process.run` throws
  /// `ProcessException` synchronously, rather than returning a nonzero
  /// exit code.
  final Set<String> notFound;

  ProcessResult _resolve(String executable, List<String> arguments) {
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
  }) async =>
      _resolve(executable, arguments);

  @override
  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      _resolve(executable, arguments);
}

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

Map<String, ProcessResult> _responses({
  bool claudeOnPath = true,
  bool gitIdentitySet = true,
  bool ghAuthed = true,
}) =>
    {
      'which git': _ok(''),
      'which gh': _ok(''),
      'which claude': claudeOnPath ? _ok('') : _fail(),
      'git config user.name': gitIdentitySet ? _ok('Aksana Buster') : _fail(),
      'git config user.email': gitIdentitySet ? _ok('ab@liitx.com') : _fail(),
      'gh auth status': ghAuthed ? _ok('') : _fail(),
    };

void main() {
  group('runDoctorChecks — tools', () {
    test('ok when git, gh, and claude are all on PATH', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: const {},
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
        env: const {},
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
        env: const {},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final auth = outcomes.firstWhere((o) => o.id == HarnessCheckId.ghAuth);
      expect(auth.result, equals(HarnessCheckResult.fail));
    });

    test('git missing entirely: gitIdentity fails instead of throwing ProcessException', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(), notFound: const {'git'}),
        env: const {},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final identity = outcomes.firstWhere((o) => o.id == HarnessCheckId.gitIdentity);
      expect(identity.result, equals(HarnessCheckResult.fail));
    });

    test('which itself missing: tools fails instead of throwing ProcessException', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(), notFound: const {'which'}),
        env: const {},
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
        env: const {},
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
        env: const {},
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
        env: const {},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final auth = outcomes.firstWhere((o) => o.id == HarnessCheckId.ghAuth);
      expect(auth.result, equals(HarnessCheckResult.ok));
    });

    test('fails when gh auth status exits non-zero', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses(ghAuthed: false)),
        env: const {},
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
        env: const {'ANTHROPIC_API_KEY': 'sk-ant-test'},
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
        env: const {},
        projectRoot: '/fake/repo',
        io: MemoryFileIO(),
      );
      final provider = outcomes.firstWhere((o) => o.id == HarnessCheckId.providerEnv);
      expect(provider.result, equals(HarnessCheckResult.skip));
    });

    test('ok when a provider is configured only in ~/.claude/settings.json, not process env', () async {
      final outcomes = await runDoctorChecks(
        runner: _FakeProcessRunner(_responses()),
        env: const {},
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

  group('runDoctor exit code', () {
    test('exits 0 when every check is ok or skip', () async {
      _ExitException? caught;
      try {
        await runDoctor(
          runner: _FakeProcessRunner(_responses()),
          env: const {},
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
          env: const {},
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
