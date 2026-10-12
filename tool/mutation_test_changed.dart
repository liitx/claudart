// mutation_test_changed.dart — runs mutation_test automatically against
// every changed lib/ file paired with its mirrored test file, instead of a
// human naming one FILE/TEST_FILE pair by hand every run (`make
// mutation-test`, still the right tool for a single targeted file).
//
// Safety, not speed, is this script's whole reason to exist. `mutation_test`
// mutates FILE on disk and reverts it itself on a clean exit — but issue
// #77 (confirmed, reproduced several times, filed against the upstream
// tool, not something this script can fix) shows that revert never happens
// if the process has to be killed: an orphaned `frontend_server_aot`
// survives `mutation_test`'s own internal timeout and keeps a pipe open
// forever, so the whole invocation hangs well past any timeout meant to
// bound it. This script assumes every run might need to be killed and
// defends against that, rather than trusting the tool's own revert:
//   1. Snapshot the file before the run.
//   2. Kill the WHOLE process tree before restoring anything, on a timeout
//      OR an interrupt (SIGINT/SIGTERM) — collecting every descendant PID
//      first, since the orphan that caused #77 is still attached under a
//      live parent at the moment of killing. Confirmed by independent
//      review: an earlier version of this script restored the snapshot on
//      Ctrl-C but never killed the process, which could keep mutating the
//      file seconds after "restore" ran, and separately left the whole
//      tree running. Kill first, unconditionally, for every exit path.
//   3. Restore the snapshot after the kill (clean exit, timeout, or
//      interrupt) — a safe no-op when the tool's own revert already
//      worked, the only thing that matters when it didn't.
//   4. Refuse to start if a leftover snapshot is found — that means a
//      prior run was itself killed before step 3 could run, and the real
//      file on disk may be mutated right now.
//
// No hardcoded skip list for #77's file: a skip list goes stale the moment
// that issue is fixed upstream, a timeout doesn't.
//
// Calls `dart run mutation_test` directly rather than going through `make
// mutation-test` — confirmed by independent review that `make` collapses
// mutation_test's own exit(-1) ("mutations survived") to exit 2, the same
// code it uses for "recipe failed" generically, so the survived/error
// distinction below was previously unreachable. Generates its own config
// (mirroring the Makefile target's content, including
// tool/dart_mutation_rules.xml) at a path unique to this process, not the
// Makefile target's fixed path, so a concurrent manual `make mutation-test`
// run can't clobber this script's config mid-run.

import 'dart:convert';
import 'dart:io';

const _defaultTimeoutMinutes = 10;
const _snapshotDir = '/tmp/claudart_mutation_test/snapshots';
const _configDir = '/tmp/claudart_mutation_test/configs';
const _rulesFile = 'tool/dart_mutation_rules.xml';
const _gitExecutable = 'git';
const _libPrefix = 'lib/';
const _dartSuffix = '.dart';
const _cleanStatus = 'CLEAN';
const _drainTimeout = Duration(seconds: 10);

String? _activeSnapshotLib;
String? _activeSnapshotPath;
Process? _activeProcess;
String? _activeConfigPath;

void main(List<String> args) async {
  final timeoutMinutes =
      args.isNotEmpty ? int.tryParse(args[0]) ?? _defaultTimeoutMinutes : _defaultTimeoutMinutes;

  void onInterrupt(ProcessSignal signal) {
    _killActiveProcessTree();
    _restoreActiveSnapshotIfAny();
    final configPath = _activeConfigPath;
    if (configPath != null && File(configPath).existsSync()) File(configPath).deleteSync();
    stderr.writeln('\nInterrupted (${signal.name}).');
    exit(130);
  }

  ProcessSignal.sigint.watch().listen(onInterrupt);
  ProcessSignal.sigterm.watch().listen(onInterrupt);

  final snapshotDir = Directory(_snapshotDir);
  if (snapshotDir.existsSync() && snapshotDir.listSync(recursive: true).whereType<File>().isNotEmpty) {
    stderr.writeln(
      '✗ Leftover snapshot(s) found under $_snapshotDir — a previous run was killed before '
      'it could restore its file. The real file on disk may still be mutated. Compare each '
      'snapshot against its lib/ counterpart by hand, restore if needed, then delete '
      '$_snapshotDir before running again.',
    );
    exit(2);
  }

  final changed = _changedLibFiles();
  if (changed.isEmpty) {
    print('No changed lib/ files.');
    exit(0);
  }

  var anyFailed = false;
  for (final libFile in changed) {
    final testFile = _mirrorTestFor(libFile);
    if (testFile == null || !File(testFile).existsSync()) {
      print('SKIPPED    $libFile (no mirrored test file)');
      continue;
    }
    final status = await _runOne(libFile, testFile, timeoutMinutes);
    print('$status    $libFile');
    if (status != _cleanStatus) anyFailed = true;
  }

  exit(anyFailed ? 1 : 0);
}

List<String> _changedLibFiles() {
  final mergeBaseResult = Process.runSync(_gitExecutable, ['merge-base', 'main', 'HEAD']);
  final mergeBase = mergeBaseResult.stdout.toString().trim();
  if (mergeBase.isEmpty) {
    stderr.writeln(
      '✗ `git merge-base main HEAD` returned nothing — is there a local `main` branch? '
      'Cannot determine what changed without it.',
    );
    exit(2);
  }
  // --diff-filter=d excludes deletions: a deleted lib/ file has nothing to
  // snapshot or mutate, and without this filter a stale mirrored test
  // could reach the snapshot step and crash on a file that no longer
  // exists.
  final diffOut = Process.runSync(
    _gitExecutable,
    ['diff', '--name-only', '--diff-filter=d', mergeBase],
  ).stdout.toString();
  final untrackedOut =
      Process.runSync(_gitExecutable, ['ls-files', '--others', '--exclude-standard']).stdout.toString();
  final all = <String>{...diffOut.split('\n'), ...untrackedOut.split('\n')};
  return all.where((f) => f.startsWith(_libPrefix) && f.endsWith(_dartSuffix)).toList()..sort();
}

/// `lib/a/b.dart` -> `test/a/b_test.dart`. Null for anything not actually
/// under `lib/` with a `.dart` extension (defensive; `_changedLibFiles`
/// already filters to this shape).
String? _mirrorTestFor(String libPath) {
  if (!libPath.startsWith(_libPrefix) || !libPath.endsWith(_dartSuffix)) return null;
  final middle = libPath.substring(_libPrefix.length, libPath.length - _dartSuffix.length);
  return 'test/$middle' '_test.dart';
}

Future<String> _runOne(String libFile, String testFile, int timeoutMinutes) async {
  final snapshotPath = '$_snapshotDir/$libFile';
  Directory(File(snapshotPath).parent.path).createSync(recursive: true);
  File(libFile).copySync(snapshotPath);
  _activeSnapshotLib = libFile;
  _activeSnapshotPath = snapshotPath;

  final configPath = _writeConfig(libFile, testFile);
  _activeConfigPath = configPath;
  try {
    final process = await Process.start('dart', ['run', 'mutation_test', '-b', '-f', 'md', configPath]);
    _activeProcess = process;
    final stdoutDone = process.stdout.transform(utf8.decoder).drain<void>();
    final stderrDone = process.stderr.transform(utf8.decoder).drain<void>();

    final timedOut = await Future.any([
      process.exitCode.then((_) => false),
      Future.delayed(Duration(minutes: timeoutMinutes), () => true),
    ]);

    if (timedOut) {
      _killProcessTree(process);
      await process.exitCode;
      return 'TIMED OUT';
    }

    final code = await process.exitCode;
    // Mirrors the timeout path's own defense: a descendant that outlives a
    // *normal* exit (the #77 shape, just without the timeout firing) could
    // hold `process.stdout`/`stderr` open and hang these drains forever
    // with nothing bounding them otherwise.
    await Future.wait([stdoutDone, stderrDone]).timeout(_drainTimeout, onTimeout: () => []);
    return switch (code) {
      0 => _cleanStatus,
      -1 || 255 => 'SURVIVED (see mutation-test-report/)',
      _ => 'ERROR (exit $code)',
    };
  } finally {
    _activeProcess = null;
    _restoreSnapshot(libFile, snapshotPath);
    if (File(configPath).existsSync()) File(configPath).deleteSync();
    _activeConfigPath = null;
  }
}

/// Writes this run's own mutation_test config — the same content as the
/// Makefile's `mutation-test` target, at a path unique to this process
/// (not that target's fixed path) so a concurrent manual run can't
/// overwrite it mid-run.
String _writeConfig(String libFile, String testFile) {
  Directory(_configDir).createSync(recursive: true);
  final configPath = '$_configDir/pid${pid}_${libFile.replaceAll('/', '_')}.xml';
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<mutations version="1.2">')
    ..writeln(File(_rulesFile).readAsStringSync())
    ..writeln('  <files><file>$libFile</file></files>')
    ..writeln(
      '  <commands><command group="test" expected-return="0" timeout="60">dart test $testFile</command></commands>',
    )
    ..writeln('</mutations>');
  File(configPath).writeAsStringSync(buffer.toString());
  return configPath;
}

void _killActiveProcessTree() {
  final process = _activeProcess;
  if (process != null) _killProcessTree(process);
}

/// Collects every descendant before killing anything — once a kill starts
/// cascading, a still-live parent's own children can no longer be
/// discovered through it.
void _killProcessTree(Process process) {
  final descendants = _descendantPids(process.pid);
  for (final pid in descendants) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
  process.kill(ProcessSignal.sigkill);
}

/// Every descendant of [pid], recursively — `mutation_test` -> `dart test`
/// -> `frontend_server_aot` is 2 levels deep, and nothing guarantees it
/// always will be.
List<int> _descendantPids(int pid) {
  final result = Process.runSync('pgrep', ['-P', '$pid']);
  final direct = (result.stdout as String)
      .split('\n')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
  return [
    for (final child in direct) ...[child, ..._descendantPids(child)],
  ];
}

void _restoreSnapshot(String libFile, String snapshotPath) {
  final snapshot = File(snapshotPath);
  if (snapshot.existsSync()) {
    File(libFile).writeAsBytesSync(snapshot.readAsBytesSync());
    snapshot.deleteSync();
  }
  _activeSnapshotLib = null;
  _activeSnapshotPath = null;
}

void _restoreActiveSnapshotIfAny() {
  final libFile = _activeSnapshotLib;
  final snapshotPath = _activeSnapshotPath;
  if (libFile != null && snapshotPath != null) {
    _restoreSnapshot(libFile, snapshotPath);
  }
}
