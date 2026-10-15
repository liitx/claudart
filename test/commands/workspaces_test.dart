import 'dart:convert';

import 'package:claudart/claudart.dart' as api;
import 'package:claudart/commands/workspaces.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart' show blankHandoff;
import 'package:claudart/workspace/workspace_link_state.dart';
import 'package:test/test.dart';

import '../conformance/lifecycle_scenarios.dart';
import '../helpers/mocks.dart';

const _primaryProject = defaultLifecycleProject;
const _siblingProject = siblingLifecycleProject;
const _bothProjects = [_primaryProject, _siblingProject];
const _setupThroughSuggest = 'setup, suggest, kill';

/// What `runWorkspaces` prints for a caller standing in [projectRoot].
Future<String> _listingAs(MemoryFileIO io, String projectRoot) async {
  final listingSink = StringBuffer();
  await runWorkspaces(
    io: io,
    projectRootOverride: projectRoot,
    listingSink: listingSink,
  );
  return listingSink.toString();
}

Future<MemoryFileIO> _bothLinked() async {
  final io = freshLifecycleIo(defaultLifecycleEnvironment, _bothProjects);
  // A holds a live session at readyForDebug; B has only a blank handoff.
  final steps =
      lifecycleScenarios(project: _primaryProject)[_setupThroughSuggest]!;
  for (final step in steps.take(2)) {
    await quietly(() => step.run(io));
  }
  io.write(handoffPathFor(_siblingProject.workspace), blankHandoff);
  return io;
}

void main() {
  test('the interaction outcomes are the documented wire values', () {
    expect(
      WorkspaceInteraction.workspacesListed.outcomeFor(workspaceCount: 2),
      'listed 2 workspaces',
    );
    expect(
      WorkspaceInteraction.projectTargeted.outcomeFor(),
      'targeted-by-project',
    );
  });

  test(
      'the listing and the selector are part of the public library zedup '
      'imports', () async {
    final io = await _bothLinked();
    final summaries = api.summarizeWorkspaces(api.Registry.load(io: io), io);
    expect(summaries, isA<List<api.WorkspaceSummary>>());
    expect(api.HandoffEvent.values, isNotEmpty);
    expect(api.HandoffTransition, isNotNull);
    expect(
      api.selectProject(api.Registry.load(io: io), 'my-app'),
      isA<api.ProjectSelected>(),
    );
  });

  group('summarizeWorkspaces', () {
    test('lists every linked workspace, sorted by name', () async {
      final io = await _bothLinked();
      final summaries = summarizeWorkspaces(Registry.load(io: io), io);
      expect(summaries.map((s) => s.name), ['my-app', 'other-app']);
    });

    test('each summary carries the registry facts', () async {
      final io = await _bothLinked();
      final b = summarizeWorkspaces(Registry.load(io: io), io)
          .singleWhere((s) => s.name == 'other-app');
      expect(b.projectRoot, _siblingProject.root);
      expect(b.workspacePath, _siblingProject.workspace);
      expect(b.lastSession, '2026-03-15');
    });

    test(
        'status is the effective status: a live session shows its own, a '
        'blank handoff is noHandoff', () async {
      final io = await _bothLinked();
      final byName = {
        for (final s in summarizeWorkspaces(Registry.load(io: io), io))
          s.name: s.status,
      };
      expect(byName, {
        'my-app': HandoffStatus.readyForDebug,
        'other-app': HandoffStatus.noHandoff,
      });
    });

    test('a workspace with no handoff file is noHandoff', () {
      final io =
          freshLifecycleIo(defaultLifecycleEnvironment, [_primaryProject]);
      expect(
        summarizeWorkspaces(Registry.load(io: io), io).single.status,
        HandoffStatus.noHandoff,
      );
    });

    test('the link state is read from each project root', () {
      final io = MemoryFileIO(
        links: {'${_primaryProject.root}/.claude'},
        dirs: {
          '${_siblingProject.root}/.claude',
          _primaryProject.root,
          _siblingProject.root,
        },
      );
      Registry.empty()
          .add(RegistryEntry(
            name: _primaryProject.name,
            projectRoot: _primaryProject.root,
            workspacePath: _primaryProject.workspace,
            createdAt: '2026-01-01',
            lastSession: '2026-03-15',
          ))
          .add(RegistryEntry(
            name: _siblingProject.name,
            projectRoot: _siblingProject.root,
            workspacePath: _siblingProject.workspace,
            createdAt: '2026-01-01',
            lastSession: '2026-03-15',
          ))
          .save(io: io);
      final states = {
        for (final s in summarizeWorkspaces(Registry.load(io: io), io))
          s.name: s.linkState,
      };
      expect(states, {
        'my-app': WorkspaceLinkState.symlinked,
        'other-app': WorkspaceLinkState.realDirectory,
      });
    });

    test('a locked workspace is reported locked, the other is not', () async {
      final io = await _bothLinked();
      io.write('${_primaryProject.workspace}/workspace.lock', 'setup');
      final locked = {
        for (final s in summarizeWorkspaces(Registry.load(io: io), io))
          s.name: s.locked,
      };
      expect(locked, {'my-app': true, 'other-app': false});
    });

    test(
        'exactly the workspace whose root is the current directory is '
        'marked current', () async {
      final io = await _bothLinked();
      final current = {
        for (final s in summarizeWorkspaces(
          Registry.load(io: io),
          io,
          currentProjectRoot: _siblingProject.root,
        ))
          s.name: s.isCurrent,
      };
      expect(current, {'my-app': false, 'other-app': true});
    });

    test('with no current directory, none is current', () async {
      final io = await _bothLinked();
      expect(
        summarizeWorkspaces(Registry.load(io: io), io)
            .where((s) => s.isCurrent),
        isEmpty,
      );
    });
  });

  group('WorkspaceSummary.toJson', () {
    test('uses enum names and plain values, exactly', () async {
      final io = await _bothLinked();
      final json = summarizeWorkspaces(
        Registry.load(io: io),
        io,
        currentProjectRoot: _primaryProject.root,
      ).first.toJson();
      expect(json, {
        'name': 'my-app',
        'projectRoot': '/projects/my-app',
        'workspacePath': '/workspaces/my-app',
        'status': 'readyForDebug',
        'hasSession': true,
        'linkState': 'symlinked',
        'locked': false,
        'lastSession': '2026-03-15',
        'current': true,
      });
    });

    test('hasSession is false exactly when the status is noHandoff', () async {
      final io = await _bothLinked();
      final byName = {
        for (final s in summarizeWorkspaces(Registry.load(io: io), io))
          s.name: s.toJson()['hasSession'],
      };
      expect(byName, {'my-app': true, 'other-app': false});
    });
  });

  group('runWorkspaces', () {
    String interactionsLogOf(MemoryFileIO io, LifecycleProject project) =>
        io.read('${logsDirFor(project.workspace)}/interactions.jsonl');

    test('writes the listing to the sink', () async {
      final io = await _bothLinked();
      final listing = await _listingAs(io, _primaryProject.root);
      expect(listing, contains('other-app'));
      expect(listing, startsWith('  WORKSPACE'));
    });

    test('the table header lines up with its rows', () async {
      final io = await _bothLinked();
      final listing = await _listingAs(io, _primaryProject.root);
      final lines = listing.split('\n');
      final row = lines.firstWhere((l) => l.contains('other-app'));
      // The LOCKED value ('no') sits under its header, after the link state.
      expect(
        row.indexOf('no', row.indexOf(WorkspaceLinkState.symlinked.name)),
        lines.first.indexOf('LOCKED'),
      );
    });

    test('logs the listing in the asking workspace only', () async {
      final io = await _bothLinked();
      final before = interactionsLogOf(io, _primaryProject);
      await runWorkspaces(
        io: io,
        projectRootOverride: _primaryProject.root,
        listingSink: StringBuffer(),
      );
      final added =
          interactionsLogOf(io, _primaryProject).substring(before.length);
      final logged = jsonDecode(added.trim()) as Map;
      expect(logged['command'], 'workspaces');
      expect(logged['outcome'], WorkspaceInteraction.workspacesListed
          .outcomeFor(workspaceCount: 2));
      expect(interactionsLogOf(io, _siblingProject), isEmpty);
    });

    test('from an unlinked directory it lists but logs nowhere', () async {
      final io = await _bothLinked();
      final before = interactionsLogOf(io, _primaryProject);
      final listing = await _listingAs(io, '/elsewhere');
      expect(listing, contains('my-app'));
      expect(interactionsLogOf(io, _primaryProject), before);
      expect(interactionsLogOf(io, _siblingProject), isEmpty);
    });
  });

  group('renderWorkspaces', () {
    test('json: one object with a workspaces array', () async {
      final io = await _bothLinked();
      final summaries = summarizeWorkspaces(Registry.load(io: io), io);
      final decoded = jsonDecode(renderWorkspaces(summaries, asJson: true))
          as Map<String, dynamic>;
      expect(decoded.keys, ['workspaces']);
      expect((decoded['workspaces'] as List).map((w) => (w as Map)['name']), [
        'my-app',
        'other-app',
      ]);
    });

    test(
        'text: a header, one row per workspace (current marked), and the '
        'targeting hint', () async {
      final io = await _bothLinked();
      final text = renderWorkspaces(
        summarizeWorkspaces(
          Registry.load(io: io),
          io,
          currentProjectRoot: _primaryProject.root,
        ),
        asJson: false,
      );
      final lines = text.split('\n');
      expect(lines.first, contains('WORKSPACE'));
      expect(lines.firstWhere((l) => l.contains('my-app')), startsWith('*'));
      expect(
        lines.firstWhere((l) => l.contains('other-app')),
        startsWith(' '),
      );
      expect(text, contains('ready-for-debug'));
      expect(text, contains('no-handoff'));
      expect(text, contains('claudart --project <name> <command>'));
    });

    test('text: no linked workspaces says so', () {
      expect(
        renderWorkspaces(const [], asJson: false),
        contains('No linked workspaces'),
      );
    });
  });
}
