// workspace_scope_test.dart — sessions are scoped to their own workspace.
//
// Two projects are linked in one registry. These tests prove that what claudart
// generates and does for one is invisible to the other: the slash-command files
// name only their own workspace, and every command in every lifecycle step
// leaves the other workspace byte-identical. A command run from a directory
// that is not a linked project changes nothing at all.

import 'package:claudart/commands/kill.dart';
import 'package:claudart/commands/link.dart';
import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/registry.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';
import 'lifecycle_scenarios.dart';

const _a = defaultLifecycleProject;
const _b = siblingLifecycleProject;
const _both = [_a, _b];

/// Every file the project owns: its workspace and its repo root.
Map<String, String> _filesOf(MemoryFileIO io, LifecycleProject project) => {
      for (final entry in io.files.entries)
        if (entry.key.startsWith('${project.workspace}/') ||
            entry.key.startsWith('${project.root}/'))
          entry.key: entry.value,
    };

/// The registry entry for [project], as a comparable map.
Map<String, Object?> _registryEntryOf(
  MemoryFileIO io,
  LifecycleProject project,
) {
  final entry = Registry.load(io: io).findByName(project.name)!;
  return {
    'name': entry.name,
    'projectRoot': entry.projectRoot,
    'workspacePath': entry.workspacePath,
    'createdAt': entry.createdAt,
    'lastSession': entry.lastSession,
    'sensitivityMode': entry.sensitivityMode,
  };
}

Iterable<String> _commandFiles(MemoryFileIO io, LifecycleProject project) =>
    io.files.keys.where(
      (path) => path.startsWith('${project.workspace}/.claude/commands/'),
    );

void main() {
  group('generated slash commands name only their own workspace', () {
    late final io = () {
      final io = freshLifecycleIo(defaultLifecycleEnvironment, _both);
      for (final project in _both) {
        createProjectLinks(
          projectRoot: project.root,
          workspace: project.workspace,
          effectiveName: project.name,
          fileIO: io,
        );
      }
      return io;
    }();

    for (final project in _both) {
      final other = project == _a ? _b : _a;

      test('${project.name}: one file per command-bearing flow', () {
        final expected = AgentFlow.values.where((f) => f.hasCommandFile);
        expect(
          _commandFiles(io, project).map((p) => p.split('/').last).toSet(),
          {for (final flow in expected) flow.fileName(project.name)},
        );
      });

      // How each flow finds its workspace. Independent literal table.
      //   baked:   the file names the workspace path (and its CLI calls resolve
      //            the project from the current directory)
      //   runtime: the file asks `claudart status`, i.e. the current directory
      const bakedPath = {
        AgentFlow.suggest,
        AgentFlow.debug,
        AgentFlow.save,
        AgentFlow.teardown,
      };
      const runtimeResolved = {AgentFlow.setup, AgentFlow.flow};

      test('the table covers every command-bearing flow', () {
        expect(
          {...bakedPath, ...runtimeResolved},
          AgentFlow.values.where((f) => f.hasCommandFile).toSet(),
        );
      });

      for (final flow in AgentFlow.values.where((f) => f.hasCommandFile)) {
        test(
            '${project.name}/${flow.name}: finds its workspace '
            '${bakedPath.contains(flow) ? 'by a baked path' : 'at run time'}',
            () {
          final content = io.read(
            '${project.workspace}/.claude/commands/'
            '${flow.fileName(project.name)}',
          );
          expect(
            content.contains(project.workspace),
            bakedPath.contains(flow),
          );
          expect(
            content.contains('claudart status'),
            runtimeResolved.contains(flow),
          );
        });
      }

      test('${project.name}: no file mentions the other workspace', () {
        for (final path in _commandFiles(io, project)) {
          final content = io.read(path);
          expect(content, isNot(contains(other.workspace)), reason: path);
          expect(content, isNot(contains(other.root)), reason: path);
        }
      });
    }
  });

  group('a lifecycle in one workspace leaves the other byte-identical', () {
    for (final entry in {
      'A runs, B watches': (_a, _b),
      'B runs, A watches': (_b, _a)
    }.entries) {
      final (runner, watcher) = entry.value;
      for (final scenario in lifecycleScenarios(project: runner).entries) {
        test('${entry.key}: ${scenario.key}', () async {
          final io = freshLifecycleIo(defaultLifecycleEnvironment, _both);

          // Bring the watcher to a live session first.
          for (final step
              in lifecycleScenarios(project: watcher)['setup, suggest, kill']!
                  .take(2)) {
            await quietly(() => step.run(io));
          }
          final filesBefore = _filesOf(io, watcher);
          final registryBefore = _registryEntryOf(io, watcher);
          expect(filesBefore, isNotEmpty, reason: 'the watcher has a session');

          for (final step in scenario.value) {
            await quietly(() => step.run(io));
            expect(
              _filesOf(io, watcher),
              filesBefore,
              reason: '${runner.name} ${step.name} changed ${watcher.name}',
            );
            expect(
              _registryEntryOf(io, watcher),
              registryBefore,
              reason: '${runner.name} ${step.name} touched ${watcher.name}\'s '
                  'registry entry',
            );
          }
        });
      }
    }
  });

  group('a command run outside any linked project changes nothing', () {
    test('kill from an unregistered directory exits 1 and writes nothing',
        () async {
      final io = freshLifecycleIo(defaultLifecycleEnvironment, _both);
      for (final project in _both) {
        await quietly(
          () => lifecycleScenarios(project: project)['setup, kill']!
              .first
              .run(io),
        );
      }
      final before = Map<String, String>.of(io.files);

      await expectLater(
        quietly(
          () => runKill(
            io: io,
            projectRootOverride: '/projects/stranger',
            confirmFn: (_) => true,
            exitFn: (code) => throw StateError('exit($code)'),
          ),
        ),
        throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'exit(1)')),
      );
      expect(io.files, before);
    });
  });
}
