// doctor.dart — `claudart doctor`, the fresh-machine verification harness
//
// Runs each HarnessCheckId once, prints one [OK]/[SKIP]/[FAIL] line per
// check, exits 1 if any check failed. Idempotent — safe to re-run after
// fixing a failure, each check re-reads live state rather than caching.

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../file_io.dart';
import '../git_utils.dart';
import '../harness/harness_check.dart';
import '../logging/logger.dart';
import '../paths.dart';
import '../process_runner.dart';
import '../providers/agent_provider.dart';
import '../providers/claude_settings_env.dart';
import '../registry.dart';

const _gitExecutable = 'git';
const _ghExecutable = 'gh';
const _claudeExecutable = 'claude';
const _awsExecutable = 'aws';
const _requiredTools = [_gitExecutable, _ghExecutable, _claudeExecutable];
const _doctorCommandName = 'doctor';
const _ec2MetadataDisabledVar = 'AWS_EC2_METADATA_DISABLED';
const _notUsingBedrockDetail = 'not using Bedrock';
const _defaultBedrockPreflightTimeout = Duration(seconds: 10);
const _whichExecutable = 'which';
const _authStatusArgs = ['auth', 'status'];
const _githooksDirName = '.githooks';

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
  Duration? bedrockPreflightTimeout,
}) async {
  final proc = runner ?? const RealProcessRunner();
  final fileIO = io ?? const RealFileIO();
  final environment = env ?? Platform.environment;
  final root = projectRoot ?? Directory.current.path;

  final activeProvider = await _detectActiveProvider(proc, environment, io: io, settingsPath: claudeSettingsPath);

  // `claude` itself reads Bedrock config from either the shell or
  // ~/.claude/settings.json's own `env` block — confirmed on a real
  // Bedrock-only machine where the flag lives *only* in settings.json.
  // Checking process env alone false-[FAIL]s on exactly that machine, the
  // same blind spot `providerEnv` already had before `detectEffective`.
  final mergedEnv = {
    ...readClaudeSettingsEnv(io: fileIO, path: claudeSettingsPath),
    ...environment,
  };

  return [
    await _checkTools(proc),
    await _checkGitIdentity(proc, root),
    await _checkGhAuth(proc),
    _checkProviderEnv(env, io: io, settingsPath: claudeSettingsPath),
    _checkWorkspaceRoot(environment, fileIO),
    _checkRegistryHealth(fileIO),
    _checkPathConfiguration(environment),
    _checkBedrockMetadataDisabled(activeProvider, mergedEnv),
    await _checkBedrockCredentialsPreflight(
      activeProvider,
      proc,
      env: mergedEnv,
      timeout: bedrockPreflightTimeout ?? _defaultBedrockPreflightTimeout,
    ),
    await _checkGitHooksConfigured(proc, root, fileIO),
  ];
}

/// Ground truth for "is Bedrock actually active right now" — prefers the
/// real `claude auth status` JSON (see
/// [AgentProvider.detectFromAuthStatusJson]) over env-var inference, since
/// the two gate-checks below only make sense when Bedrock is genuinely the
/// resolved provider, not merely "some Bedrock-shaped env vars exist".
/// Falls back to [AgentProvider.detectEffective] when `claude auth status`
/// itself isn't available or doesn't parse (e.g. `claude` genuinely
/// missing — already surfaced separately by [_checkTools]).
Future<AgentProvider?> _detectActiveProvider(
  ProcessRunner proc,
  Map<String, String> env, {
  FileIO? io,
  String? settingsPath,
}) async {
  final result = await _tryRun(proc, _claudeExecutable, _authStatusArgs);
  final fromAuthStatus = AgentProvider.detectFromAuthStatusJson(result.stdout as String? ?? '');
  return fromAuthStatus ??
      AgentProvider.detectEffective(processEnv: env, io: io, settingsPath: settingsPath);
}

Future<HarnessCheckOutcome> _checkTools(ProcessRunner proc) async {
  final missing = <String>[];
  for (final tool in _requiredTools) {
    final result = await _tryRun(proc, _whichExecutable, [tool]);
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
  final name = readGitConfig(GitConfigKey.userName, workingDirectory: root, runner: proc);
  final email = readGitConfig(GitConfigKey.userEmail, workingDirectory: root, runner: proc);
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

Future<HarnessCheckOutcome> _checkGhAuth(ProcessRunner proc) async {
  final result = await _tryRun(proc, _ghExecutable, _authStatusArgs);
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

/// `CLAUDART_WORKSPACE` being unset isn't itself wrong (the `~/.claudart`
/// fallback is a valid, documented default) — but it's exactly the
/// condition under which a process can silently diverge from whatever
/// registry a shell-exported override points at elsewhere on the same
/// machine. Surfaced as `skip`, not `fail`: flagging a deliberately
/// supported configuration as broken would be worse than staying quiet.
///
/// Confirmed against a real cross-machine test: echoing the variable
/// alone isn't enough. Also checks (a) the resolved directory actually
/// exists — a typo'd override is worse than no override, and (b) whether
/// `~/.claudart` *also* holds a registry when the override points
/// elsewhere — that second registry is exactly the split-brain condition
/// this check exists for, invisible to any process that inherits the
/// override correctly and never looks at the fallback at all.
HarnessCheckOutcome _checkWorkspaceRoot(Map<String, String> env, FileIO io) {
  final home = env[homeEnvVar] ?? '';
  final fallbackRoot = p.join(home, '.claudart');
  final value = env[claudartWorkspaceEnvVar];

  if (value == null || value.isEmpty) {
    return (
      id: HarnessCheckId.workspaceRoot,
      result: HarnessCheckResult.skip,
      detail: 'CLAUDART_WORKSPACE not set in this process — using the '
          '~/.claudart fallback. If a shell elsewhere on this machine '
          'exports a different value, that is two diverging registries, '
          'not one',
    );
  }

  final resolvedRoot =
      value.startsWith('~/') ? p.join(home, value.substring(2)) : value;

  if (!io.dirExists(resolvedRoot)) {
    return (
      id: HarnessCheckId.workspaceRoot,
      result: HarnessCheckResult.fail,
      detail: 'CLAUDART_WORKSPACE=$value does not exist on disk',
    );
  }

  final fallbackRegistry = p.join(fallbackRoot, registryFileName);
  if (resolvedRoot != fallbackRoot && io.fileExists(fallbackRegistry)) {
    return (
      id: HarnessCheckId.workspaceRoot,
      result: HarnessCheckResult.fail,
      detail: 'CLAUDART_WORKSPACE=$value is set, but $fallbackRegistry '
          'also exists — any process that does not inherit this override '
          'will silently use that one instead. This is the real '
          'split-brain, not just the possibility of one',
    );
  }

  return (
    id: HarnessCheckId.workspaceRoot,
    result: HarnessCheckResult.ok,
    detail: 'CLAUDART_WORKSPACE=$value',
  );
}

/// `Registry.load` (`lib/registry.dart`) silently swallows a JSON parse
/// failure and returns an empty registry — correct for its own callers
/// (a wizard flow failing shouldn't crash over a corrupt file), but it
/// means a corrupt registry.json and a genuinely-fresh one were
/// indistinguishable from doctor's output alone. This re-reads the raw
/// file to tell those two apart before falling through to `Registry.load`.
HarnessCheckOutcome _checkRegistryHealth(FileIO io) {
  if (!io.fileExists(registryPath)) {
    return (
      id: HarnessCheckId.registryHealth,
      result: HarnessCheckResult.skip,
      detail: 'no registry entries yet at $workspacesRoot — nothing linked',
    );
  }

  final raw = io.read(registryPath);
  if (raw.trim().isEmpty) {
    return (
      id: HarnessCheckId.registryHealth,
      result: HarnessCheckResult.skip,
      detail: 'registry.json exists but is empty at $workspacesRoot',
    );
  }

  try {
    jsonDecode(raw);
  } on FormatException {
    return (
      id: HarnessCheckId.registryHealth,
      result: HarnessCheckResult.fail,
      detail: 'registry.json exists at $workspacesRoot but failed to '
          'parse — back it up and investigate before linking anything new',
    );
  }

  final registry = Registry.load(io: io);
  if (registry.isEmpty) {
    return (
      id: HarnessCheckId.registryHealth,
      result: HarnessCheckResult.skip,
      detail: 'registry.json parses but has no entries yet',
    );
  }
  final stale = [
    for (final entry in registry.entries)
      if (!io.dirExists(entry.projectRoot)) entry.name,
  ];
  return stale.isEmpty
      ? (
          id: HarnessCheckId.registryHealth,
          result: HarnessCheckResult.ok,
          detail: '${registry.entries.length} '
              '${registry.entries.length == 1 ? 'entry' : 'entries'}, '
              'all projectRoots exist',
        )
      : (
          id: HarnessCheckId.registryHealth,
          result: HarnessCheckResult.fail,
          detail: 'stale entries (projectRoot missing): ${stale.join(', ')}',
        );
}

HarnessCheckOutcome _checkBedrockMetadataDisabled(
  AgentProvider? activeProvider,
  Map<String, String> env,
) {
  if (activeProvider != AgentProvider.bedrock) {
    return (
      id: HarnessCheckId.bedrockMetadataDisabled,
      result: HarnessCheckResult.skip,
      detail: _notUsingBedrockDetail,
    );
  }
  final disabled = (env[_ec2MetadataDisabledVar] ?? '').toLowerCase() == 'true';
  return disabled
      ? (
          id: HarnessCheckId.bedrockMetadataDisabled,
          result: HarnessCheckResult.ok,
          detail: '$_ec2MetadataDisabledVar=true',
        )
      : (
          id: HarnessCheckId.bedrockMetadataDisabled,
          result: HarnessCheckResult.fail,
          detail: '$_ec2MetadataDisabledVar is not set to true — a broken '
              'Bedrock profile on a non-EC2 host does not fail fast, it '
              'stalls probing the EC2 instance metadata service (measured: '
              '740s) before erroring. Set $_ec2MetadataDisabledVar=true '
              'unless this machine is a real EC2 instance',
        );
}

HarnessCheckOutcome _checkPathConfiguration(Map<String, String> env) {
  final home = env[homeEnvVar] ?? '';
  final binDir = '$home/bin';
  final path = env['PATH'] ?? '';
  final onPath = path.split(':').contains(binDir);
  return onPath
      ? (
          id: HarnessCheckId.pathConfiguration,
          result: HarnessCheckResult.ok,
          detail: '$binDir is on PATH',
        )
      : (
          id: HarnessCheckId.pathConfiguration,
          result: HarnessCheckResult.fail,
          detail: '$binDir is not on PATH — claudart compile/zedup setup '
              'install there; a freshly-built binary would be unreachable',
        );
}

/// "Bedrock is configured" (the right env vars are present) is not the
/// same fact as "Bedrock will work" — this confirms credentials actually
/// resolve with a real, bounded call before anything spawns `claude`
/// against them. Bounded deliberately: without
/// [HarnessCheckId.bedrockMetadataDisabled] already failing this *and*
/// something still invoking `aws` directly, a hung preflight would itself
/// become exactly the multi-minute stall this harness exists to catch.
/// Never prints the resolved identity (account ID/ARN) — only whether it
/// resolved.
Future<HarnessCheckOutcome> _checkBedrockCredentialsPreflight(
  AgentProvider? activeProvider,
  ProcessRunner proc, {
  required Map<String, String> env,
  required Duration timeout,
}) async {
  if (activeProvider != AgentProvider.bedrock) {
    return (
      id: HarnessCheckId.bedrockCredentialsPreflight,
      result: HarnessCheckResult.skip,
      detail: _notUsingBedrockDetail,
    );
  }
  final which = await _tryRun(proc, _whichExecutable, [_awsExecutable]);
  if (which.exitCode != 0) {
    return (
      id: HarnessCheckId.bedrockCredentialsPreflight,
      result: HarnessCheckResult.skip,
      detail: 'aws CLI not found — cannot preflight credentials',
    );
  }
  try {
    // [env] (process env merged with settings.json's own block) is passed
    // explicitly — AWS_PROFILE/AWS_REGION can live in settings.json only,
    // same as the Bedrock flag itself; a bare inherited-env subprocess
    // call missed that on a real Bedrock-only machine.
    final result = await proc.runKillable(
      _awsExecutable,
      ['sts', 'get-caller-identity'],
      environment: env,
      timeout: timeout,
    );
    return result.exitCode == 0
        ? (
            id: HarnessCheckId.bedrockCredentialsPreflight,
            result: HarnessCheckResult.ok,
            detail: 'AWS credentials resolve correctly',
          )
        : (
            id: HarnessCheckId.bedrockCredentialsPreflight,
            result: HarnessCheckResult.fail,
            detail: 'aws sts get-caller-identity failed — check '
                'AWS_PROFILE and that the session is still valid',
          );
  } on TimeoutException {
    return (
      id: HarnessCheckId.bedrockCredentialsPreflight,
      result: HarnessCheckResult.fail,
      detail: 'aws sts get-caller-identity did not respond within '
          '${timeout.inSeconds}s — credentials cannot be verified',
    );
  }
}

/// Mirrors `link.dart`'s own `_ensureHooksPath` check: a project without a
/// tracked `.githooks/` dir has nothing to configure (skip, not fail — most
/// projects don't use this convention yet). One that has it but isn't
/// pointed at it is the exact gap that let a real pre-push protection
/// (zedup's own) exist on only one machine, invisible to every fresh clone.
Future<HarnessCheckOutcome> _checkGitHooksConfigured(
  ProcessRunner proc,
  String root,
  FileIO io,
) async {
  if (!io.dirExists(p.join(root, _githooksDirName))) {
    return (
      id: HarnessCheckId.gitHooksConfigured,
      result: HarnessCheckResult.skip,
      detail: 'no .githooks/ in this project',
    );
  }
  final configured = readGitConfig(GitConfigKey.hooksPath, workingDirectory: root, runner: proc);
  return configured == _githooksDirName
      ? (
          id: HarnessCheckId.gitHooksConfigured,
          result: HarnessCheckResult.ok,
          detail: 'core.hooksPath=.githooks',
        )
      : (
          id: HarnessCheckId.gitHooksConfigured,
          result: HarnessCheckResult.fail,
          detail: '.githooks/ exists but core.hooksPath is not set to it — '
              'run `git config core.hooksPath .githooks`, or re-run '
              '`claudart link`',
        );
}

/// CLI entry point: runs every check, prints each outcome, logs the run
/// (so it's visible later via `claudart report` instead of only whatever
/// gets pasted into chat), exits 1 if any failed (0 if clean or skip-only).
Future<void> runDoctor({
  ProcessRunner? runner,
  Map<String, String>? env,
  String? projectRootOverride,
  FileIO? io,
  String? claudeSettingsPath,
  String? workspacePath,
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

  final failed = [
    for (final o in outcomes)
      if (o.result == HarnessCheckResult.fail) o,
  ];
  final logger = SessionLogger(io: io, workspacePath: workspacePath);
  logger.logInteraction(
    command: _doctorCommandName,
    outcome: failed.isEmpty ? 'ok' : 'failed',
    platform: Platform.operatingSystem,
  );
  for (final outcome in failed) {
    logger.logError(
      command: _doctorCommandName,
      errorType: 'harness_check_failed',
      fingerprint: 'doctor.${outcome.id.name}',
      reason: outcome.detail,
    );
  }

  exit_(failed.isEmpty ? 0 : 1);
}
