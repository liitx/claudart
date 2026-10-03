@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Regression: on macOS Dart reports `stdin.hasTerminal == true` for
/// `/dev/null`, so `claudart link` (and every menu) used to die with an
/// unhandled `StdinException` (errno 19) as soon as it prompted — and the
/// hidden-cursor escape was left behind. This runs the real entrypoint with
/// stdin redirected from /dev/null.
void main() {
  test('link with stdin from /dev/null prompts without crashing', () async {
    final tmp = Directory.systemTemp.createTempSync('nontty_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(proj.path, 'pubspec.yaml')).writeAsStringSync('name: proj\n');
    for (final args in [
      ['init', '-q'],
      ['add', '-A'],
      ['-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-qm', 'init'],
    ]) {
      final r = await Process.run('git', args, workingDirectory: proj.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    final dart = Platform.resolvedExecutable;
    final script = p.join(Directory.current.path, 'bin', 'claudart.dart');
    final result = await Process.run(
      'sh',
      ['-c', '"$dart" "$script" link proj </dev/null'],
      workingDirectory: proj.path,
      environment: {'CLAUDART_WORKSPACE': p.join(tmp.path, 'ws')},
    );

    final output = '${result.stdout}${result.stderr}';
    expect(output, isNot(contains('Unhandled exception')), reason: output);
    expect(output, isNot(contains('StdinException')), reason: output);
    expect(output, contains('Registered: proj'), reason: output);
    expect(result.exitCode, 0, reason: output);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
