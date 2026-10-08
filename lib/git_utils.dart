import 'dart:io';

import 'process_runner.dart';

/// Result of a single git context detection — project root and current branch.
/// Both are null when the working directory is not inside a git repository.
typedef GitContext = ({String root, String branch});

/// Git author name/email, read from `git config` in [projectRoot]. Either
/// field is null when unset — a fresh clone with no user-level git config
/// has neither, and this must not throw for that case.
typedef GitAuthor = ({String? name, String? email});

/// A single `git config` key this codebase reads or writes — the literal
/// key string lives here once, not re-typed at every call site. Three
/// independent implementations of "read/write a git config value" existed
/// before this (`git_utils.dart` itself, `doctor.dart`'s `_gitConfig`,
/// `link.dart`'s inline `hooksPath` reads/writes) — none sharing the fix
/// below, so two of three were still vulnerable to the same leaked-env
/// corruption class `#65` closed only for the test helper.
enum GitConfigKey {
  userName(gitKey: 'user.name'),
  userEmail(gitKey: 'user.email'),
  hooksPath(gitKey: 'core.hooksPath');

  const GitConfigKey({required this.gitKey});

  /// The literal key `git config` itself expects.
  final String gitKey;
}

const _gitExecutable = 'git';
const _detachedHeadMarker = 'HEAD';

/// The executable + leading args every git call goes through to clear
/// GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE — exposed (not private) so a test's
/// fake `ProcessRunner` can build the exact subprocess invocation to key on,
/// instead of re-typing these flags as a second, separately-maintained
/// string.
const gitEnvClearExecutable = 'env';
const gitEnvClearArgs = ['-u', 'GIT_DIR', '-u', 'GIT_WORK_TREE', '-u', 'GIT_INDEX_FILE'];
const _gitConfigSubcommand = 'config';

/// Runs a git subcommand with GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE cleared.
///
/// Confirmed real, not hypothetical: a push from a linked worktree arrives
/// with these set by git itself, pointed at that worktree's own
/// `.git/worktrees/<name>`. Left inherited, every `git` subprocess a
/// leaked-env caller spawns can silently redirect into the wrong repo —
/// one incident flipped a shared `.git/config`'s `core.worktree` and
/// landed a stray commit on `main`. Passing `environment: {}` to
/// `Process.run`/`runSync` only *merges* onto the parent env, it cannot
/// un-inherit an already-set var — `env -u` is the one way that actually
/// clears it for the child.
ProcessResult _runGit(
  ProcessRunner proc,
  List<String> gitArgs, {
  required String workingDirectory,
}) =>
    proc.runSync(
      gitEnvClearExecutable,
      [...gitEnvClearArgs, _gitExecutable, ...gitArgs],
      workingDirectory: workingDirectory,
    );

/// Detects the git project root and current branch in one process spawn.
///
/// Uses `git rev-parse --show-toplevel --abbrev-ref HEAD` so both values
/// are resolved from a single subprocess call. Returns null when the
/// working directory is not inside a git repository or in detached HEAD
/// state where no branch name is available. [runner] is injectable for
/// tests; production defaults to a real process.
GitContext? detectGitContext({ProcessRunner? runner}) {
  final proc = runner ?? const RealProcessRunner();
  try {
    final result = _runGit(
      proc,
      ['rev-parse', '--show-toplevel', '--abbrev-ref', _detachedHeadMarker],
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final root = lines[0].trim();
    final branch = lines[1].trim();
    // Detached HEAD returns literal "HEAD" — treat as no branch.
    if (root.isEmpty || branch.isEmpty || branch == _detachedHeadMarker) return null;
    return (root: root, branch: branch);
  } on ProcessException catch (_) {
    return null;
  }
}

/// Reads [key] from `git config` in [workingDirectory]. Never throws — an
/// unset key (or no git repo at all) returns null rather than failing the
/// caller. [runner] is injectable for tests.
String? readGitConfig(
  GitConfigKey key, {
  required String workingDirectory,
  ProcessRunner? runner,
}) {
  final proc = runner ?? const RealProcessRunner();
  try {
    final result = _runGit(proc, [_gitConfigSubcommand, key.gitKey], workingDirectory: workingDirectory);
    if (result.exitCode != 0) return null;
    final value = (result.stdout as String).trim();
    return value.isEmpty ? null : value;
  } on ProcessException catch (_) {
    return null;
  }
}

/// Writes [value] to [key] in `git config` under [workingDirectory]. Not a
/// real git repo, or `git` itself unavailable: silently no-ops, same
/// never-throw contract as [readGitConfig]. [runner] is injectable for
/// tests.
void writeGitConfig(
  GitConfigKey key,
  String value, {
  required String workingDirectory,
  ProcessRunner? runner,
}) {
  final proc = runner ?? const RealProcessRunner();
  try {
    _runGit(proc, [_gitConfigSubcommand, key.gitKey, value], workingDirectory: workingDirectory);
  } on ProcessException catch (_) {
    // Not a git repo, or git itself unavailable — nothing to configure.
  }
}

/// Reads `git config user.name` / `user.email` from [projectRoot]. Never
/// throws — a fresh repo with no configured author returns both fields
/// null rather than failing the caller's wizard flow. [runner] is
/// injectable for tests.
GitAuthor readGitAuthor(String projectRoot, {ProcessRunner? runner}) => (
      name: readGitConfig(GitConfigKey.userName, workingDirectory: projectRoot, runner: runner),
      email: readGitConfig(GitConfigKey.userEmail, workingDirectory: projectRoot, runner: runner),
    );

/// Resolves the project root the same way for every command: an explicit
/// override wins, otherwise fall back to the git repository root. Never the
/// process cwd — a command run from a subdirectory must still find it.
String? resolveProjectRoot({String? override}) =>
    override ?? detectGitContext()?.root;
