@TestOn('mac-os || linux')
library;

import 'package:test/test.dart';

import '../helpers/cli_session.dart';

/// Process-level checks of `claudart rotate` as a script (zedup, CI) sees it:
/// no terminal, so the only ways through are `--headless` or an answer on stdin,
/// and a failed build gate has to show up in the exit code.
void main() {
  const passingGate = 'rebuild:\n\t@echo ok\n';

  test('rotate with nothing on stdin stops with exit 1 and leaves the session alone', () async {
    final s = await CliSession.create(makefile: passingGate);
    final r = await s.run(['rotate']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('No input available'), reason: r.out);
    expect(r.out, contains('--headless'), reason: r.out);
    expect(r.out, isNot(contains('Running build gate')), reason: 'the gate command must not run');
    expect((await s.run(['status'])).out, isNot(contains('No active handoff')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotate --headless with a passing gate succeeds (exit 0)', () async {
    final s = await CliSession.create(makefile: passingGate);
    final r = await s.run(['rotate', '--headless']);

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('headless'), reason: r.out);
    expect(r.out, contains('Build passed'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotate --headless with a failing gate exits 1 and names afterFixCommand', () async {
    final s = await CliSession.create(); // no Makefile, so the default `make rebuild` fails
    final r = await s.run(['rotate', '--headless']);

    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('Build failed'), reason: r.out);
    expect(r.out, contains('afterFixCommand'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a piped yes still counts as an answer', () async {
    final s = await CliSession.create(makefile: passingGate);
    final r = await s.run(['rotate'], stdin: 'y\n');

    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('Build passed'), reason: r.out);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
