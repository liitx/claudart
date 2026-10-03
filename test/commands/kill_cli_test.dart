@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/cli_session.dart';

/// `claudart kill` exactly as zedup's chat pane runs it: a subprocess with an
/// empty stdin. Before `--headless` this always ended in "Kill cancelled" and
/// never killed anything.
void main() {
  Future<String> status(CliSession s) async => (await s.run(['status'])).out;

  test('kill with nothing on stdin stops with exit 1 (not a fake "cancelled") and keeps the session', () async {
    final s = await CliSession.create();
    final r = await s.run(['kill']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('No input available'), reason: r.out);
    expect(r.out, contains('--headless'), reason: r.out);
    expect(r.out, isNot(contains('Session killed')), reason: r.out);
    expect(await status(s), isNot(contains('No active handoff')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('kill --headless kills: archive written, link kept, exit 0', () async {
    final s = await CliSession.create();
    final r = await s.run(['kill', '--headless']);

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('headless'), reason: r.out);
    expect(r.out, contains('Session killed'), reason: r.out);
    expect(Directory(p.join(s.ws.path, 'proj', 'archive')).listSync(), isNotEmpty);
    // The registration (the .claude link) survives a kill; only unlink removes it.
    expect(Link(p.join(s.proj.path, '.claude')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a piped yes still kills', () async {
    final s = await CliSession.create();
    final r = await s.run(['kill'], stdin: 'y\n');

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('Session killed'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('kill --headless refuses to clear a workspace lock', () async {
    final s = await CliSession.create();
    File(p.join(s.ws.path, 'proj', 'workspace.lock')).writeAsStringSync('setup');
    final r = await s.run(['kill', '--headless']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('never clears a workspace lock'), reason: r.out);
    expect(r.out, isNot(contains('Session killed')), reason: r.out);
    expect(File(p.join(s.ws.path, 'proj', 'workspace.lock')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
