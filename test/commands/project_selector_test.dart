import 'dart:convert';

import 'package:claudart/commands/project_selector.dart';
import 'package:claudart/commands/workspaces.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

Registry _registry() => Registry.empty()
    .add(const RegistryEntry(
      name: 'my-app',
      projectRoot: '/projects/my-app',
      workspacePath: '/workspaces/my-app',
      createdAt: '2026-01-01',
      lastSession: '2026-03-15',
    ))
    .add(const RegistryEntry(
      name: 'other-app',
      projectRoot: '/projects/other-app',
      workspacePath: '/workspaces/other-app',
      createdAt: '2026-01-01',
      lastSession: '2026-03-15',
    ));

void main() {
  group('extractProjectOption', () {
    test('no option leaves the arguments untouched', () {
      final r = extractProjectOption(['status', '--prompt']);
      expect(r.args, ['status', '--prompt']);
      expect(r.name, isNull);
      expect(r.missingValue, isFalse);
    });

    test('--project NAME is removed wherever it appears', () {
      expect(
        extractProjectOption(['--project', 'my-app', 'status']).args,
        ['status'],
      );
      expect(
        extractProjectOption(['status', '--project', 'my-app']).args,
        ['status'],
      );
      expect(
        extractProjectOption(['preflight', '--project', 'my-app', 'debug'])
            .args,
        ['preflight', 'debug'],
      );
    });

    test('--project=NAME is the same as --project NAME', () {
      final r = extractProjectOption(['--project=my-app', 'status']);
      expect(r.name, 'my-app');
      expect(r.args, ['status']);
    });

    test('the name is returned', () {
      expect(extractProjectOption(['--project', 'x', 'status']).name, 'x');
    });

    test('a trailing --project with no value is reported, not swallowed', () {
      final r = extractProjectOption(['status', '--project']);
      expect(r.missingValue, isTrue);
      expect(r.name, isNull);
      expect(r.args, ['status']);
    });

    test('--project followed by another flag is a missing value', () {
      final r = extractProjectOption(['--project', '--headless', 'kill']);
      expect(r.missingValue, isTrue);
      expect(r.args, ['--headless', 'kill']);
    });

    test('an empty --project= is a missing value', () {
      expect(
          extractProjectOption(['--project=', 'status']).missingValue, isTrue);
    });
  });

  group('selectProject', () {
    test('no name selects nothing', () {
      expect(selectProject(_registry(), null), isA<NoProjectSelected>());
    });

    test('a registered name selects its entry', () {
      final selection = selectProject(_registry(), 'other-app');
      expect(selection, isA<ProjectSelected>());
      expect((selection as ProjectSelected).entry.projectRoot,
          '/projects/other-app');
    });

    test('an unknown name lists the linked workspaces, sorted', () {
      final selection = selectProject(_registry(), 'nope');
      expect(selection, isA<ProjectNotFound>());
      final notFound = selection as ProjectNotFound;
      expect(notFound.name, 'nope');
      expect(notFound.known, ['my-app', 'other-app']);
    });

    test('names match exactly, not by prefix or case', () {
      expect(selectProject(_registry(), 'my'), isA<ProjectNotFound>());
      expect(selectProject(_registry(), 'MY-APP'), isA<ProjectNotFound>());
    });

    test('an empty registry has nothing to select', () {
      final selection = selectProject(Registry.empty(), 'my-app');
      expect((selection as ProjectNotFound).known, isEmpty);
    });
  });

  group('ProjectNotFound.message', () {
    test('names the project and lists what is linked', () {
      final selection = selectProject(_registry(), 'nope') as ProjectNotFound;
      expect(
        selection.message,
        "Unknown project 'nope'. Linked workspaces: my-app, other-app. "
        'Run `claudart workspaces` to see them.',
      );
    });

    test('with nothing linked, says to link one', () {
      final selection = selectProject(Registry.empty(), 'x') as ProjectNotFound;
      expect(
        selection.message,
        "Unknown project 'x'. No workspaces are linked; run `claudart link` "
        'in a project first.',
      );
    });
  });

  group('logProjectTargeted', () {
    final entry = _registry().entries.first;
    final other = _registry().entries.last;
    String interactionsLogOf(MemoryFileIO io, RegistryEntry entry) =>
        io.read('${logsDirFor(entry.workspacePath)}/interactions.jsonl');

    test('the outcome is the documented wire value', () {
      expect(
        WorkspaceInteraction.projectTargeted.outcomeFor(),
        'targeted-by-project',
      );
    });

    test('records the command and outcome in the targeted workspace only', () {
      final io = MemoryFileIO();
      logProjectTargeted(entry, 'status', io: io);
      final logged = jsonDecode(interactionsLogOf(io, entry).trim()) as Map;
      expect(logged['command'], 'status');
      expect(
        logged['outcome'],
        WorkspaceInteraction.projectTargeted.outcomeFor(),
      );
      expect(interactionsLogOf(io, other), isEmpty);
    });

    test('a second targeting appends, so the log shows each one', () {
      final io = MemoryFileIO();
      logProjectTargeted(entry, 'status', io: io);
      logProjectTargeted(entry, 'kill', io: io);
      final commands = [
        for (final line in interactionsLogOf(io, entry).trim().split('\n'))
          (jsonDecode(line) as Map)['command'],
      ];
      expect(commands, ['status', 'kill']);
    });

    test('carries the workspace sensitivity mode', () {
      final io = MemoryFileIO();
      logProjectTargeted(
        RegistryEntry(
          name: entry.name,
          projectRoot: entry.projectRoot,
          workspacePath: entry.workspacePath,
          createdAt: entry.createdAt,
          lastSession: entry.lastSession,
          sensitivityMode: true,
        ),
        'status',
        io: io,
      );
      final logged = jsonDecode(interactionsLogOf(io, entry).trim()) as Map;
      expect(logged['sensitivityMode'], isTrue);
    });
  });
}
