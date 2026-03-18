import 'dart:io';

/// Result of a single git context detection — project root and current branch.
/// Both are null when the working directory is not inside a git repository.
typedef GitContext = ({String root, String branch});

/// Detects the git project root and current branch in one process spawn.
///
/// Uses `git rev-parse --show-toplevel --abbrev-ref HEAD` so both values
/// are resolved from a single subprocess call. Returns null when the
/// working directory is not inside a git repository or in detached HEAD
/// state where no branch name is available.
GitContext? detectGitContext() {
  try {
    final result = Process.runSync(
      'git',
      ['rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD'],
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final root = lines[0].trim();
    final branch = lines[1].trim();
    // Detached HEAD returns literal "HEAD" — treat as no branch.
    if (root.isEmpty || branch.isEmpty || branch == 'HEAD') return null;
    return (root: root, branch: branch);
  } on ProcessException catch (_) {
    return null;
  }
}
