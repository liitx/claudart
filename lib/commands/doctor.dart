// doctor.dart — `claudart doctor`, the fresh-machine verification harness
//
// Runs each HarnessCheckId once, prints one [OK]/[SKIP]/[FAIL] line per
// check, exits 1 if any check failed. Idempotent — safe to re-run after
// fixing a failure, each check re-reads live state rather than caching.

import 'dart:io';

import '../file_io.dart';
import '../harness/harness_check.dart';
import '../process_runner.dart';
import '../providers/agent_provider.dart';

const _requiredTools = ['git', 'gh', 'claude'];

/// `ProcessRunner.run` is backed by `Process.run`, which throws
/// `ProcessException` synchronously when [executable] isn't found at all
/// (not just a nonzero exit) — e.g. `gh` genuinely missing on a fresh
/// machine. A harness whose whole purpose is surfacing exactly that case
/// must not crash on it; this converts the exception into the same shape
/// as a failed run (exit 127, the shell convention for "command not
/// found"), so every check downstream only ever has to handle exit codes.
Future<ProcessResult> _tryRun(
  ProcessRunner proc,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  try {
    return await proc.run(executable, arguments, workingDirectory: workingDirectory);
  } on ProcessException catch (e) {
    return ProcessResult(0, 127, '', e.message);
  }
}

/// Runs every harness check and returns their outcomes, in declaration
/// order. Injectable [runner]/[env]/[projectRoot] — no real subprocess or
/// ambient-environment dependency in tests.
Future<List<HarnessCheckOutcome>> runDoctorChecks({
  ProcessRunner? runner,
  Map<String, String>? env,
  String? projectRoot,
  FileIO? io,
  String? claudeSettingsPath,
}) async {
  final proc = runner ?? const RealProcessRunner();
  final root = projectRoot ?? Directory.current.path;

  return [
    await _checkTools(proc),
    await _checkGitIdentity(proc, root),
    await _checkGhAuth(proc),
    _checkProviderEnv(env, io: io, settingsPath: claudeSettingsPath),
  ];
}

Future<HarnessCheckOutcome> _checkTools(ProcessRunner proc) async {
  final missing = <String>[];
  for (final tool in _requiredTools) {
    final result = await _tryRun(proc, 'which', [tool]);
    if (result.exitCode != 0) missing.add(tool);
  }
  return missing.isEmpty
      ? (
          id: HarnessCheckId.tools,
          result: HarnessCheckResult.ok,
          detail: '${_requiredTools.join(', ')} all on PATH',
        )
      : (
          id: HarnessCheckId.tools,
          result: HarnessCheckResult.fail,
          detail: 'missing: ${missing.join(', ')}',
        );
}

Future<HarnessCheckOutcome> _checkGitIdentity(ProcessRunner proc, String root) async {
  final name = await _gitConfig(proc, root, 'user.name');
  final email = await _gitConfig(proc, root, 'user.email');
  if (name != null && email != null) {
    return (
      id: HarnessCheckId.gitIdentity,
      result: HarnessCheckResult.ok,
      detail: '$name <$email>',
    );
  }
  return (
    id: HarnessCheckId.gitIdentity,
    result: HarnessCheckResult.fail,
    detail: 'user.name/user.email not set for this repo',
  );
}

Future<String?> _gitConfig(ProcessRunner proc, String root, String key) async {
  final result = await _tryRun(proc, 'git', ['config', key], workingDirectory: root);
  if (result.exitCode != 0) return null;
  final value = (result.stdout as String).trim();
  return value.isEmpty ? null : value;
}

Future<HarnessCheckOutcome> _checkGhAuth(ProcessRunner proc) async {
  final result = await _tryRun(proc, 'gh', ['auth', 'status']);
  return result.exitCode == 0
      ? (
          id: HarnessCheckId.ghAuth,
          result: HarnessCheckResult.ok,
          detail: 'active login found',
        )
      : (
          id: HarnessCheckId.ghAuth,
          result: HarnessCheckResult.fail,
          detail: 'gh auth status failed — run `gh auth login`',
        );
}

HarnessCheckOutcome _checkProviderEnv(
  Map<String, String>? processEnv, {
  FileIO? io,
  String? settingsPath,
}) {
  final provider = AgentProvider.detectEffective(
    processEnv: processEnv,
    io: io,
    settingsPath: settingsPath,
  );
  if (provider != null) {
    return (
      id: HarnessCheckId.providerEnv,
      result: HarnessCheckResult.ok,
      detail: '${provider.name} configured',
    );
  }
  return (
    id: HarnessCheckId.providerEnv,
    result: HarnessCheckResult.skip,
    detail: 'no provider found in this process\'s environment or '
        '~/.claude/settings.json — fine for OAuth login',
  );
}

/// CLI entry point: runs every check, prints each outcome, exits 1 if any
/// failed (0 if clean or skip-only).
Future<void> runDoctor({
  ProcessRunner? runner,
  Map<String, String>? env,
  String? projectRootOverride,
  FileIO? io,
  String? claudeSettingsPath,
  Never Function(int code)? exitFn,
}) async {
  final exit_ = exitFn ?? exit;
  final outcomes = await runDoctorChecks(
    runner: runner,
    env: env,
    projectRoot: projectRootOverride,
    io: io,
    claudeSettingsPath: claudeSettingsPath,
  );
  for (final outcome in outcomes) {
    print(formatHarnessOutcome(outcome));
  }
  final hasFailure = outcomes.any((o) => o.result == HarnessCheckResult.fail);
  exit_(hasFailure ? 1 : 0);
}
