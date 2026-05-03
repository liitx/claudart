import 'dart:async';
import 'dart:convert';
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
Future<GitContext?> detectGitContext() async {
  try {
    final process = await Process.start(
      'git',
      ['rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD'],
      workingDirectory: Directory.current.path,
    );

    final timeout = Duration(seconds: 10);
    final timer = Timer(timeout, () => process.kill());

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    process.stdout.listen(
      (data) => stdoutBuffer.write(utf8.decode(data)),
      onDone: () {},
    );
    process.stderr.listen(
      (data) => stderrBuffer.write(utf8.decode(data)),
      onDone: () {},
    );

    final exitCode = await process.exitCode;
    timer.cancel();

    if (exitCode != 0) return null;

    final stdout = stdoutBuffer.toString().trim();
    final lines = stdout.split('\n');

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
