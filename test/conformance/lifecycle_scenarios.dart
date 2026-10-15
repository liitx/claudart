// lifecycle_scenarios.dart — the lifecycle scenarios and their driver.
//
// Shared by test/conformance/lifecycle_test.dart (claudart's own suite) and
// tool/consumer_check (which replays the same scenarios against zedup's real
// reader), so the two cannot drift apart. Each step drives one real claudart
// command in memory; `effective` is an independent literal for the status a
// consumer should see afterwards.

import 'dart:async';
import 'dart:convert';

import 'package:claudart/commands/debug.dart';
import 'package:claudart/commands/kill.dart';
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/commands/setup.dart';
import 'package:claudart/commands/suggest.dart';
import 'package:claudart/commands/teardown.dart';
import 'package:claudart/md_io.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/workspace/workspace_link_state.dart';
import 'package:path/path.dart' as p;

import '../helpers/mocks.dart';

/// A linked project: its registry name, repo root and claudart workspace.
typedef LifecycleProject = ({String name, String root, String workspace});

const defaultLifecycleProject = (
  name: 'my-app',
  root: '/projects/my-app',
  workspace: '/workspaces/my-app',
);

/// A second linked project, for scoping tests across workspaces.
const siblingLifecycleProject = (
  name: 'other-app',
  root: '/projects/other-app',
  workspace: '/workspaces/other-app',
);

String _claudeLink(LifecycleProject project) => '${project.root}/.claude';
const _setupAnswers = [
  'fix/null-ref',
  'Some bug.',
  'Some expected.',
  'loader.dart',
  null,
];
const _analysis = '<ROOT_CAUSE>rc</ROOT_CAUSE>'
    '<SCOPE_FILES>- `lib/foo.dart`</SCOPE_FILES>'
    '<SCOPE_ENTRIES>f()</SCOPE_ENTRIES><SCOPE_CLASSES>Foo</SCOPE_CLASSES>'
    '<MUST_NOT_TOUCH>x</MUST_NOT_TOUCH><CONSTRAINTS>c</CONSTRAINTS>';

Never _noExit(int code) => throw StateError('exit($code)');

/// The environment a lifecycle runs in: how the project is linked to its
/// workspace, and whether its pubspec declares dartrix.
typedef LifecycleEnvironment = ({WorkspaceLinkState link, bool usesDartrix});

/// Every link state x dartrix on/off.
List<LifecycleEnvironment> lifecycleEnvironments() => [
      for (final link in WorkspaceLinkState.values)
        for (final usesDartrix in [false, true])
          (link: link, usesDartrix: usesDartrix),
    ];

String describeEnvironment(LifecycleEnvironment env) =>
    '${env.link.name}, ${env.usesDartrix ? 'with' : 'without'} dartrix';

const _dartrixPubspec = 'name: my_app\n'
    'dev_dependencies:\n'
    '  dartrix:\n'
    '    git:\n'
    '      url: https://github.com/liitx/dartrix.git\n';

/// The default environment: linked by symlink, no dartrix (what the unit tests
/// and the zedup consumer check have always used).
const defaultLifecycleEnvironment = (
  link: WorkspaceLinkState.symlinked,
  usesDartrix: false,
);

/// An in-memory filesystem with every project in [projects] registered and
/// linked as [env] says.
MemoryFileIO freshLifecycleIo([
  LifecycleEnvironment env = defaultLifecycleEnvironment,
  List<LifecycleProject> projects = const [defaultLifecycleProject],
]) {
  final io = MemoryFileIO(
    dirs: {
      for (final project in projects) ...{
        project.root,
        if (env.link == WorkspaceLinkState.realDirectory) _claudeLink(project),
      },
    },
    links: {
      if (env.link == WorkspaceLinkState.symlinked)
        for (final project in projects) _claudeLink(project),
    },
    files: {
      if (env.usesDartrix)
        for (final project in projects)
          '${project.root}/pubspec.yaml': _dartrixPubspec,
    },
  );
  var registry = Registry.empty();
  for (final project in projects) {
    registry = registry.add(
      RegistryEntry(
        name: project.name,
        projectRoot: project.root,
        workspacePath: project.workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      ),
    );
  }
  registry.save(io: io);
  return io;
}

PipelineExecutor _exec(String text) => PipelineExecutor(
      runner: ({
        required model,
        required systemPrompt,
        required message,
        required workingDir,
        StepMode mode = StepMode.project,
      }) async =>
          StepResult(
        text: text,
        usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
      ),
    );

Future<void> quietly(Future<void> Function() body) => runZoned(
      body,
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );

// -- Steps (each drives one real command) --------------------------------

Future<void> setup(
  MemoryFileIO io, {
  int menu = 0,
  LifecycleProject project = defaultLifecycleProject,
}) {
  final answers = _setupAnswers.iterator;
  return runSetup(
    io: io,
    projectRootOverride: project.root,
    confirmFn: (_) => true,
    promptFn: (q, {optional = false}) =>
        answers.moveNext() ? answers.current : null,
    pickFn: (_) => menu,
    exitFn: _noExit,
    fileFinderFn: (_, __) => [],
  );
}

Future<void> suggest(
  MemoryFileIO io, {
  LifecycleProject project = defaultLifecycleProject,
}) =>
    runSuggest(
      io: io,
      projectRootOverride: project.root,
      exitFn: _noExit,
      executor: _exec(_analysis),
      confirmFn: (_) => true,
      promptFn: (q, {optional = false}) => null,
      pickFn: (_) => 0,
    );

Future<void> debug(
  MemoryFileIO io, {
  LifecycleProject project = defaultLifecycleProject,
}) =>
    runDebug(
      io: io,
      projectRootOverride: project.root,
      exitFn: _noExit,
      executor: _exec('<CHANGES>none</CHANGES>'),
      pickFn: (_) => 0,
    );

Future<void> kill(
  MemoryFileIO io, {
  LifecycleProject project = defaultLifecycleProject,
}) =>
    runKill(
      io: io,
      projectRootOverride: project.root,
      confirmFn: (_) => true,
      exitFn: _noExit,
    );

Future<void> rotate(
  MemoryFileIO io, {
  LifecycleProject project = defaultLifecycleProject,
}) async {
  await runRotate(
    io: io,
    projectRootOverride: project.root,
    exitFn: _noExit,
    confirmFn: (_) => true,
    buildFn: (_) async => true,
  );
}

Future<void> teardown(
  MemoryFileIO io, {
  LifecycleProject project = defaultLifecycleProject,
}) =>
    runTeardown(
      io: io,
      projectRootOverride: project.root,
      mode: RunMode.headless,
      exitFn: _noExit,
    );

void seedPending(
  MemoryFileIO io, [
  LifecycleProject project = defaultLifecycleProject,
]) =>
    io.write(
      handoffPathFor(project.workspace),
      updateSection(
        io.read(handoffPathFor(project.workspace)),
        'Pending Issues',
        '- [ ] Next issue to do',
      ),
    );

// -- What the step left behind --------------------------------------------

HandoffStatus effectiveStatusOf(
  MemoryFileIO io, [
  LifecycleProject project = defaultLifecycleProject,
]) {
  final file = handoffPathFor(project.workspace);
  return SessionState.parse(io.fileExists(file) ? io.read(file) : '')
      .effectiveStatus;
}

/// The raw handoff.md text, '' when the file does not exist.
String handoffContentOf(
  MemoryFileIO io, [
  LifecycleProject project = defaultLifecycleProject,
]) {
  final file = handoffPathFor(project.workspace);
  return io.fileExists(file) ? io.read(file) : '';
}

/// The last logged move's `to` (null when it was rejected or nothing logged).
String? loggedTo(
  MemoryFileIO io, [
  LifecycleProject project = defaultLifecycleProject,
]) {
  final raw =
      io.read(p.join(logsDirFor(project.workspace), 'transitions.jsonl'));
  final last = raw.split('\n').where((l) => l.isNotEmpty).lastOrNull;
  if (last == null) return null;
  final entry = jsonDecode(last) as Map<String, dynamic>;
  return entry['rejected'] == true ? null : entry['to'] as String;
}

typedef LifecycleStep = ({
  String name,
  Future<void> Function(MemoryFileIO io) run,
  HandoffStatus effective, // independent literal
  bool logged, // does this step log an applied move?
});

LifecycleStep lifecycleStep(
  String name,
  Future<void> Function(MemoryFileIO io) run,
  HandoffStatus effective, {
  bool logged = true,
}) =>
    (name: name, run: run, effective: effective, logged: logged);

/// Scenario name -> ordered steps, bound to [project]. Expected statuses are
/// literals.
Map<String, List<LifecycleStep>> lifecycleScenarios({
  LifecycleProject project = defaultLifecycleProject,
}) {
  Future<void> Function(MemoryFileIO io) bind(
    Future<void> Function(MemoryFileIO io, {LifecycleProject project}) command,
  ) =>
      (io) => command(io, project: project);

  final setupStep = lifecycleStep(
    'setup',
    (io) => setup(io, project: project),
    HandoffStatus.suggestInvestigating,
  );
  return {
    'setup, suggest, debug, teardown': [
      setupStep,
      lifecycleStep('suggest', bind(suggest), HandoffStatus.readyForDebug),
      lifecycleStep('debug', bind(debug), HandoffStatus.debugComplete),
      lifecycleStep('teardown', bind(teardown), HandoffStatus.noHandoff),
    ],
    'setup, suggest, kill': [
      setupStep,
      lifecycleStep('suggest', bind(suggest), HandoffStatus.readyForDebug),
      lifecycleStep('kill', bind(kill), HandoffStatus.noHandoff),
    ],
    'setup, kill': [
      setupStep,
      lifecycleStep('kill', bind(kill), HandoffStatus.noHandoff),
    ],
    'rotate with a pending issue seeds the next session': [
      setupStep,
      lifecycleStep('suggest', bind(suggest), HandoffStatus.readyForDebug),
      lifecycleStep(
        'seed pending',
        (io) async => seedPending(io, project),
        HandoffStatus.readyForDebug,
        logged: false,
      ),
      lifecycleStep(
        'rotate',
        bind(rotate),
        HandoffStatus.suggestInvestigating,
      ),
    ],
    'rotate with nothing pending leaves no session': [
      setupStep,
      lifecycleStep('suggest', bind(suggest), HandoffStatus.readyForDebug),
      lifecycleStep('rotate', bind(rotate), HandoffStatus.noHandoff),
    ],
  };
}

/// "Start fresh" over a live handoff, for tests that need it on its own.
Future<void> setupDefault(MemoryFileIO io) => setup(io);
Future<void> setupStartFresh(MemoryFileIO io) => setup(io, menu: 1);
