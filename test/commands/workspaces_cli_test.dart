import 'dart:convert';
import 'dart:io';

import 'package:claudart/commands/workspaces.dart';
import 'package:claudart/pipeline/debug_mode.dart'
    show kAmbientDebugSuppressedNotice;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/cli_session.dart';

// The real binary, two linked projects in one registry. `proj` has a live
// session; `other` is linked with none. Everything is run from proj's
// directory, so what proves scoping is what each command touches and shows.

Future<({CliSession proj, CliSession other})> _pair() async {
  final proj = await CliSession.create();
  final other = await proj.addProject('other');
  return (proj: proj, other: other);
}

String _handoffOf(CliSession session, String name) =>
    File(p.join(session.ws.path, name, 'handoff.md')).readAsStringSync();

/// The interactions.jsonl entries a workspace has logged, oldest first.
List<Map<String, dynamic>> _interactionsOf(CliSession session, String name) {
  final file =
      File(p.join(session.ws.path, name, 'logs', 'interactions.jsonl'));
  if (!file.existsSync()) return [];
  return [
    for (final line in file.readAsLinesSync())
      if (line.isNotEmpty) (jsonDecode(line) as Map).cast<String, dynamic>(),
  ];
}

void main() {
  group('logs', () {
    // The fixture's own setup is already logged in `proj`, so each test
    // compares a workspace's log with what it held before the command ran.
    test('workspaces records what it listed in the asking workspace only',
        () async {
      final s = await _pair();
      final before = _interactionsOf(s.proj, 'proj');
      await s.proj.run(['workspaces']);
      final added = _interactionsOf(s.proj, 'proj').skip(before.length);
      expect(added.map((e) => e['command']), ['workspaces']);
      expect(added.single['outcome'], WorkspaceInteraction.workspacesListed
          .outcomeFor(workspaceCount: 2));
      expect(_interactionsOf(s.proj, 'other'), isEmpty);
    });

    test('--project records the targeting in the named workspace only',
        () async {
      final s = await _pair();
      final before = _interactionsOf(s.proj, 'proj');
      await s.proj.run(['--project', 'other', 'status']);
      final targeted = _interactionsOf(s.proj, 'other');
      expect(targeted.map((e) => e['command']), ['status']);
      expect(
        targeted.single['outcome'],
        WorkspaceInteraction.projectTargeted.outcomeFor(),
      );
      expect(_interactionsOf(s.proj, 'proj'), before);
    });

    test('an unknown --project writes no log anywhere', () async {
      final s = await _pair();
      final before = _interactionsOf(s.proj, 'proj');
      final r = await s.proj.run(['--project', 'nope', 'status']);
      expect(r.code, 1);
      expect(_interactionsOf(s.proj, 'proj'), before);
      expect(_interactionsOf(s.proj, 'other'), isEmpty);
    });
  });

  // The env var is ambient (the settings link writes set it for every Claude
  // Code session), and the trace writes full prompts to disk: a sensitive
  // project must ignore it, and only an explicit --debug overrides that.
  group('CLAUDART_DEBUG and a sensitive project', () {
    const debugEnv = {'CLAUDART_DEBUG': '1'};

    test('the env var is ignored, with a notice, for a sensitive project',
        () async {
      final s = await _pair();
      await s.proj.run(['link', '--sensitive']);
      final r = await s.proj.run(['status'], env: debugEnv);
      expect(r.out, contains(kAmbientDebugSuppressedNotice));
    });

    test('an explicit --debug still traces it, without the notice', () async {
      final s = await _pair();
      await s.proj.run(['link', '--sensitive']);
      final r = await s.proj.run(['--debug', 'status'], env: debugEnv);
      expect(r.out, isNot(contains(kAmbientDebugSuppressedNotice)));
    });

    test('a project that is not sensitive keeps the env var, with no notice',
        () async {
      final s = await _pair();
      final r = await s.proj.run(['status'], env: debugEnv);
      expect(r.out, isNot(contains(kAmbientDebugSuppressedNotice)));
    });

    test('with the env var unset there is no notice for a sensitive project',
        () async {
      final s = await _pair();
      await s.proj.run(['link', '--sensitive']);
      final r = await s.proj.run(['status']);
      expect(r.out, isNot(contains(kAmbientDebugSuppressedNotice)));
    });
  });

  group('claudart workspaces', () {
    test(
        'lists both linked workspaces, marks the current one, and says how '
        'to target another', () async {
      final s = await _pair();
      final r = await s.proj.run(['workspaces']);
      expect(r.code, 0, reason: r.out);
      final lines = r.out.split('\n');
      expect(lines.firstWhere((l) => l.contains('proj')), startsWith('*'));
      expect(lines.firstWhere((l) => l.contains('other')), startsWith(' '));
      expect(r.out, contains('suggest-investigating'));
      expect(r.out, contains('no-handoff'));
      expect(r.out, contains('claudart --project <name> <command>'));
    });

    test('--json is machine readable and agrees with the table', () async {
      final s = await _pair();
      final r = await s.proj.run(['workspaces', '--json']);
      expect(r.code, 0, reason: r.out);
      final workspaces = (jsonDecode(r.out) as Map)['workspaces'] as List;
      final byName = <String, Map<String, dynamic>>{
        for (final w in workspaces)
          (w as Map)['name'] as String: w.cast<String, dynamic>(),
      };
      expect(byName.keys.toSet(), {'proj', 'other'});
      expect(byName['proj']!['status'], 'suggestInvestigating');
      expect(byName['proj']!['hasSession'], isTrue);
      expect(byName['proj']!['current'], isTrue);
      expect(byName['other']!['status'], 'noHandoff');
      expect(byName['other']!['hasSession'], isFalse);
      expect(byName['other']!['current'], isFalse);
    });

    test('--project makes that workspace the current one', () async {
      final s = await _pair();
      final r =
          await s.proj.run(['--project', 'other', 'workspaces', '--json']);
      final workspaces = (jsonDecode(r.out) as Map)['workspaces'] as List;
      final current = [
        for (final w in workspaces)
          if ((w as Map)['current'] == true) w['name'],
      ];
      expect(current, ['other']);
    });
  });

  group('--project', () {
    test('status acts on the named workspace, not the current directory',
        () async {
      final s = await _pair();
      final here = await s.proj.run(['status']);
      final there = await s.proj.run(['--project', 'other', 'status']);
      expect(here.out, contains('Project  : proj'));
      expect(here.out, contains('suggest-investigating'));
      // `other` has no session, so it says so instead of showing proj's.
      expect(there.out, contains('No active handoff'));
      expect(there.out, isNot(contains('Project  : proj')));
      expect(there.out, isNot(contains('suggest-investigating')));
    });

    test('the option may come after the command', () async {
      final s = await _pair();
      final r = await s.proj.run(['status', '--project', 'other']);
      expect(r.out, contains('No active handoff'));
    });

    test('--project=NAME works too', () async {
      final s = await _pair();
      final r = await s.proj.run(['--project=other', 'status']);
      expect(r.out, contains('No active handoff'));
    });

    test('after setup, status for the named workspace shows its own session',
        () async {
      final s = await _pair();
      await s.proj.run(
        ['--project', 'other', 'setup'],
        stdin: 'other bug\nother expected\nlib/a.dart\na\ny\n',
      );
      final there = await s.proj.run(['--project', 'other', 'status']);
      expect(there.out, contains('Project  : other'));
      expect(there.out, contains('other bug'));
    });

    test(
        'a write lands only in the named workspace: setup for other, run '
        'from proj, leaves proj byte-identical', () async {
      final s = await _pair();
      final projBefore = _handoffOf(s.proj, 'proj');
      final r = await s.proj.run(
        ['--project', 'other', 'setup'],
        stdin: 'other bug\nother expected\nlib/a.dart\na\ny\n',
      );
      expect(r.code, 0, reason: r.out);
      expect(_handoffOf(s.proj, 'other'), contains('other bug'));
      expect(_handoffOf(s.proj, 'proj'), projBefore);
    });

    test(
        'an error from the named workspace is logged there, not to the '
        'current directory\'s workspace', () async {
      final s = await _pair();
      Directory(p.join(s.proj.ws.path, 'other', 'archive')).createSync(
        recursive: true,
      );
      File(p.join(s.proj.ws.path, 'other', 'archive', 'index.json'))
          .writeAsStringSync('{not json');

      final r = await s.proj.run(['--project', 'other', 'archives']);
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains('Archive index is corrupt'));

      final otherLog =
          File(p.join(s.proj.ws.path, 'other', 'logs', 'errors.jsonl'));
      final projLog =
          File(p.join(s.proj.ws.path, 'proj', 'logs', 'errors.jsonl'));
      expect(otherLog.readAsStringSync(),
          contains('archives.archiveIndexCorrupt'));
      expect(projLog.existsSync(), isFalse);
    });

    test('an unknown name exits 1 and lists the linked workspaces', () async {
      final s = await _pair();
      final r = await s.proj.run(['--project', 'nope', 'status']);
      expect(r.code, 1);
      expect(r.out, contains("Unknown project 'nope'"));
      expect(r.out, contains('other, proj'));
    });

    test('init keeps its own --project <name> and is not hijacked', () async {
      final s = await _pair();
      final r = await s.proj.run(['init', '--project', 'brand-new']);
      expect(r.out, isNot(contains('is not supported by')));
      expect(r.out, isNot(contains('Unknown project')));
    });

    test('a command that does not act on a session says so', () async {
      final s = await _pair();
      final r = await s.proj.run(['--project', 'other', 'doctor']);
      expect(r.code, 1);
      expect(
          r.out, contains('--project is not supported by `claudart doctor`'));
    });

    test('--project with no value exits 1', () async {
      final s = await _pair();
      final r = await s.proj.run(['status', '--project']);
      expect(r.code, 1);
      expect(r.out, contains('--project needs a project name'));
    });

    test(
        'a destructive command honours it: kill --headless for other leaves '
        'proj\'s session intact', () async {
      final s = await _pair();
      await s.proj.run(
        ['--project', 'other', 'setup'],
        stdin: 'other bug\nother expected\nlib/a.dart\na\ny\n',
      );
      final projBefore = _handoffOf(s.proj, 'proj');
      final r = await s.proj.run(['--project', 'other', 'kill', '--headless']);
      expect(r.code, 0, reason: r.out);
      expect(_handoffOf(s.proj, 'proj'), projBefore);
      expect(_handoffOf(s.proj, 'other'), isNot(contains('other bug')));
    });
  });
}
