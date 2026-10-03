import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A real linked claudart session on disk, driven through the real entrypoint
/// as a subprocess, the way a script (zedup's chat pane, CI) would: no terminal,
/// stdin from a file.
class CliSession {
  CliSession._(this.proj, this.ws);

  final Directory proj;
  final Directory ws;

  static final _dart = Platform.resolvedExecutable;
  static final _script = p.join(Directory.current.path, 'bin', 'claudart.dart');

  /// Runs `claudart <args>` in the project with [stdin] as its standard input.
  Future<({int code, String out})> run(List<String> args, {String stdin = ''}) async {
    final input = File(p.join(ws.parent.path, 'stdin.txt'))..writeAsStringSync(stdin);
    final r = await Process.run(
      'sh',
      ['-c', '"$_dart" "$_script" ${args.join(' ')} < "${input.path}"'],
      workingDirectory: proj.path,
      environment: {'CLAUDART_WORKSPACE': ws.path},
    );
    return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  /// Creates a git project, then `init`, `link --no-sensitive` and `setup`.
  static Future<CliSession> create({String? makefile}) async {
    final tmp = Directory.systemTemp.createTempSync('cli_session_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
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
    final s = CliSession._(proj, Directory(p.join(tmp.path, 'ws')));
    expect((await s.run(['init'], stdin: 'y\n')).code, 0);
    expect((await s.run(['link', 'proj', '--no-sensitive'])).code, 0);
    final setup = await s.run(['setup'], stdin: 'a bug\nexpected\nlib/a.dart\na\ny\n');
    expect(setup.code, 0, reason: setup.out);
    return s;
  }
}
