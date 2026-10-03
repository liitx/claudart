@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Process-level checks of `claudart rotate` as a script (zedup, CI) sees it:
/// no terminal, so the only ways through are `--headless` or an answer on stdin,
/// and a failed build gate has to show up in the exit code.
void main() {
  final dart = Platform.resolvedExecutable;
  final script = p.join(Directory.current.path, 'bin', 'claudart.dart');

  Future<({int code, String out})> cli(Directory proj, Directory ws, List<String> args, {String stdin = ''}) async {
    final input = File(p.join(ws.parent.path, 'stdin.txt'))..writeAsStringSync(stdin);
    final r = await Process.run(
      'sh',
      ['-c', '"$dart" "$script" ${args.join(' ')} < "${input.path}"'],
      workingDirectory: proj.path,
      environment: {'CLAUDART_WORKSPACE': ws.path},
    );
    return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  Future<({Directory proj, Directory ws})> session({String? makefile}) async {
    final tmp = Directory.systemTemp.createTempSync('rotate_cli_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    final ws = Directory(p.join(tmp.path, 'ws'));
    File(p.join(proj.path, 'pubspec.yaml')).writeAsStringSync('name: proj\n');
    Directory(p.join(proj.path, 'lib')).createSync();
    File(p.join(proj.path, 'lib', 'a.dart')).writeAsStringSync('int a() => 1;\n');
    if (makefile != null) File(p.join(proj.path, 'Makefile')).writeAsStringSync(makefile);
    for (final args in [
      ['init', '-q'],
      ['add', '-A'],
      ['-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-qm', 'init'],
    ]) {
      final r = await Process.run('git', args, workingDirectory: proj.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }
    expect((await cli(proj, ws, ['init'], stdin: 'y\n')).code, 0);
    expect((await cli(proj, ws, ['link', 'proj', '--no-sensitive'])).code, 0);
    final setup = await cli(proj, ws, ['setup'], stdin: 'a bug\nexpected\nlib/a.dart\na\ny\n');
    expect(setup.code, 0, reason: setup.out);
    return (proj: proj, ws: ws);
  }

  test('rotate with nothing on stdin stops with exit 1 and leaves the session alone', () async {
    final s = await session(makefile: 'rebuild:\n\t@echo ok\n');
    final r = await cli(s.proj, s.ws, ['rotate']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('No input available'), reason: r.out);
    expect(r.out, contains('--headless'), reason: r.out);
    expect(r.out, isNot(contains('Running build gate')), reason: 'the gate command must not run');
    expect((await cli(s.proj, s.ws, ['status'])).out, isNot(contains('No active handoff')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotate --headless with a passing gate succeeds (exit 0)', () async {
    final s = await session(makefile: 'rebuild:\n\t@echo ok\n');
    final r = await cli(s.proj, s.ws, ['rotate', '--headless']);

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('headless'), reason: r.out);
    expect(r.out, contains('Build passed'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotate --headless with a failing gate exits 1 and names afterFixCommand', () async {
    final s = await session(); // no Makefile, so the default `make rebuild` fails
    final r = await cli(s.proj, s.ws, ['rotate', '--headless']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('Build failed'), reason: r.out);
    expect(r.out, contains('afterFixCommand'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a piped yes still counts as an answer', () async {
    final s = await session(makefile: 'rebuild:\n\t@echo ok\n');
    final r = await cli(s.proj, s.ws, ['rotate'], stdin: 'y\n');

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('Build passed'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
