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
import 'package:path/path.dart' as p;

import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';
const _claudeLink = '/projects/my-app/.claude';
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

MemoryFileIO freshLifecycleIo() {
  final io = MemoryFileIO(dirs: {_projectRoot}, links: {_claudeLink});
  Registry.empty()
      .add(const RegistryEntry(
        name: 'my-app',
        projectRoot: _projectRoot,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      ))
      .save(io: io);
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

Future<void> setup(MemoryFileIO io, {int menu = 0}) {
  final answers = _setupAnswers.iterator;
  return runSetup(
    io: io,
    projectRootOverride: _projectRoot,
    confirmFn: (_) => true,
    promptFn: (q, {optional = false}) =>
        answers.moveNext() ? answers.current : null,
    pickFn: (_) => menu,
    exitFn: _noExit,
    fileFinderFn: (_, __) => [],
  );
}

Future<void> suggest(MemoryFileIO io) => runSuggest(
      io: io,
      projectRootOverride: _projectRoot,
      exitFn: _noExit,
      executor: _exec(_analysis),
      confirmFn: (_) => true,
      promptFn: (q, {optional = false}) => null,
      pickFn: (_) => 0,
    );

Future<void> debug(MemoryFileIO io) => runDebug(
      io: io,
      projectRootOverride: _projectRoot,
      exitFn: _noExit,
      executor: _exec('<CHANGES>none</CHANGES>'),
      pickFn: (_) => 0,
    );

Future<void> kill(MemoryFileIO io) => runKill(
      io: io,
      projectRootOverride: _projectRoot,
      confirmFn: (_) => true,
      exitFn: _noExit,
    );

Future<void> rotate(MemoryFileIO io) async {
  await runRotate(
    io: io,
    projectRootOverride: _projectRoot,
    exitFn: _noExit,
    confirmFn: (_) => true,
    buildFn: (_) async => true,
  );
}

Future<void> teardown(MemoryFileIO io) => runTeardown(
      io: io,
      projectRootOverride: _projectRoot,
      mode: RunMode.headless,
      exitFn: _noExit,
    );

void seedPending(MemoryFileIO io) => io.write(
      handoffPathFor(_workspace),
      updateSection(
        io.read(handoffPathFor(_workspace)),
        'Pending Issues',
        '- [ ] Next issue to do',
      ),
    );

// -- What the step left behind --------------------------------------------

HandoffStatus effectiveStatusOf(MemoryFileIO io) {
  final file = handoffPathFor(_workspace);
  return SessionState.parse(io.fileExists(file) ? io.read(file) : '')
      .effectiveStatus;
}

/// The raw handoff.md text, '' when the file does not exist.
String handoffContentOf(MemoryFileIO io) {
  final file = handoffPathFor(_workspace);
  return io.fileExists(file) ? io.read(file) : '';
}

/// The last logged move's `to` (null when it was rejected or nothing logged).
String? loggedTo(MemoryFileIO io) {
  final raw = io.read(p.join(logsDirFor(_workspace), 'transitions.jsonl'));
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

Future<void> setupDefault(MemoryFileIO io) => setup(io);
Future<void> setupStartFresh(MemoryFileIO io) => setup(io, menu: 1);

/// Scenario name -> ordered steps. Expected statuses are literals.
Map<String, List<LifecycleStep>> lifecycleScenarios() {
  final setupStep = lifecycleStep(
    'setup',
    setupDefault,
    HandoffStatus.suggestInvestigating,
  );
  return {
    'setup, suggest, debug, teardown': [
      setupStep,
      lifecycleStep('suggest', suggest, HandoffStatus.readyForDebug),
      lifecycleStep('debug', debug, HandoffStatus.debugComplete),
      lifecycleStep('teardown', teardown, HandoffStatus.noHandoff),
    ],
    'setup, suggest, kill': [
      setupStep,
      lifecycleStep('suggest', suggest, HandoffStatus.readyForDebug),
      lifecycleStep('kill', kill, HandoffStatus.noHandoff),
    ],
    'setup, kill': [
      setupStep,
      lifecycleStep('kill', kill, HandoffStatus.noHandoff),
    ],
    'rotate with a pending issue seeds the next session': [
      setupStep,
      lifecycleStep('suggest', suggest, HandoffStatus.readyForDebug),
      lifecycleStep(
        'seed pending',
        (io) async => seedPending(io),
        HandoffStatus.readyForDebug,
        logged: false,
      ),
      lifecycleStep('rotate', rotate, HandoffStatus.suggestInvestigating),
    ],
    'rotate with nothing pending leaves no session': [
      setupStep,
      lifecycleStep('suggest', suggest, HandoffStatus.readyForDebug),
      lifecycleStep('rotate', rotate, HandoffStatus.noHandoff),
    ],
  };
}
