import 'dart:io';

/// Result of a single git context detection — project root and current branch.
/// Both are null when the working directory is not inside a git repository.
typedef GitContext = ({String root, String branch});

/// Git author name/email, read from `git config` in [projectRoot]. Either
/// field is null when unset — a fresh clone with no user-level git config
/// has neither, and this must not throw for that case.
typedef GitAuthor = ({String? name, String? email});

const _gitExecutable = 'git';
const _detachedHeadMarker = 'HEAD';

/// Detects the git project root and current branch in one process spawn.
///
/// Uses `git rev-parse --show-toplevel --abbrev-ref HEAD` so both values
/// are resolved from a single subprocess call. Returns null when the
/// working directory is not inside a git repository or in detached HEAD
/// state where no branch name is available.
GitContext? detectGitContext() {
  try {
    final result = Process.runSync(
      _gitExecutable,
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

/// Reads `git config user.name` / `user.email` from [projectRoot]. Never
/// throws — a fresh repo with no configured author returns both fields
/// null rather than failing the caller's wizard flow.
GitAuthor readGitAuthor(String projectRoot) {
  String? read(String key) {
    try {
      final result = Process.runSync(
        _gitExecutable,
        ['config', key],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) return null;
      final value = (result.stdout as String).trim();
      return value.isEmpty ? null : value;
    } on ProcessException catch (_) {
      return null;
    }
  }

  return (name: read('user.name'), email: read('user.email'));
}
