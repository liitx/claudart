@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Regression: on macOS Dart reports `stdin.hasTerminal == true` for
/// `/dev/null`, so `claudart link` (and every menu) used to die with an
/// unhandled `StdinException` (errno 19) as soon as it prompted, leaving the
/// hidden-cursor escape behind. These run the real entrypoint with stdin
/// redirected from /dev/null.
///
/// Since the sensitivity-mode decision, "nobody to answer" must also never be
/// turned into an answer: `link` either gets an explicit flag or stops.
void main() {
  Future<({ProcessResult result, String output, Directory tmp})> runLink(List<String> args) async {
    final tmp = Directory.systemTemp.createTempSync('nontty_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(proj.path, 'pubspec.yaml')).writeAsStringSync('name: proj\n');
    for (final gitArgs in [
      ['init', '-q'],
      ['add', '-A'],
      ['-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-qm', 'init'],
    ]) {
      final r = await Process.run('git', gitArgs, workingDirectory: proj.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    final dart = Platform.resolvedExecutable;
    final script = p.join(Directory.current.path, 'bin', 'claudart.dart');
    final result = await Process.run(
      'sh',
      ['-c', '"$dart" "$script" link ${args.join(' ')} </dev/null'],
      workingDirectory: proj.path,
      environment: {'CLAUDART_WORKSPACE': p.join(tmp.path, 'ws')},
    );
    return (result: result, output: '${result.stdout}${result.stderr}', tmp: tmp);
  }

  test('link with stdin from /dev/null and no flag stops with a clear message', () async {
    final r = await runLink(['proj']);

    expect(r.output, isNot(contains('Unhandled exception')), reason: r.output);
    expect(r.output, isNot(contains('StdinException')), reason: r.output);
    expect(r.output, contains('No input available'), reason: r.output);
    expect(r.output, contains('--no-sensitive'), reason: r.output);
    expect(r.output, isNot(contains('Registered:')), reason: r.output);
    expect(r.result.exitCode, 1, reason: r.output);
    expect(File(p.join(r.tmp.path, 'ws', 'registry.json')).existsSync(), isFalse,
        reason: 'nothing may be written when the question cannot be answered');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('link --no-sensitive with stdin from /dev/null registers without prompting', () async {
    final r = await runLink(['proj', '--no-sensitive']);

    expect(r.output, isNot(contains('Unhandled exception')), reason: r.output);
    expect(r.output, contains('Registered: proj'), reason: r.output);
    expect(r.output, contains('Sensitivity mode: OFF'), reason: r.output);
    expect(r.result.exitCode, 0, reason: r.output);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('link --sensitive with stdin from /dev/null registers with it ON', () async {
    final r = await runLink(['--sensitive']);

    expect(r.output, contains('Sensitivity mode: ON'), reason: r.output);
    expect(r.result.exitCode, 0, reason: r.output);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
