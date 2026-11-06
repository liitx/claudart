// The two gates, run and compared (docs/topology/gates.md).
//
// `debug` runs the workspace's `verificationCommand` before it records a fix as
// verified; `rotate` runs `afterFixCommand` before it seeds the next handoff.
// Both run one shell command and read its exit code. Whether they are the same
// thing, or two things that happen to look alike, is read here from real runs:
// each use case is run through the command, and what exists at the moment the
// gate runs, the call chain that reached it, the moves it logged and what is
// left afterwards are recorded.
//
//   make topology        # UPDATE_TOPOLOGY=1 rewrites the doc

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claudart/commands/debug.dart';
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/commands/support/command_seams.dart';
import 'package:claudart/config/paths.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/pipeline/edit_files.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/pipeline/xml_tags.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/md_io.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/logged_moves.dart';
import '../helpers/mocks.dart';
import '../helpers/project_fixture.dart';
import '../helpers/unscripted.dart';

const _docPath = 'docs/topology/gates.md';
const _updateEnvVar = 'UPDATE_TOPOLOGY';
const _updateEnabledValue = '1';
const _workspace = ProjectFixture.workspace;

/// What the world looked like when a gate ran.
typedef AtGate = ({
  String status,
  int archiveFiles,
  bool fixWritten,
});

/// One use case of a gate, observed.
typedef GateRun = ({
  String command,
  String useCase,
  String configKey,
  bool invoked,
  String? shellCommand,
  AtGate? atGate,
  List<String> callChain,
  String result,
  List<String> moves,
  String statusAfter,
  int archiveFilesAfter,
  bool fixLeftWritten,
});

/// The claudart frames of [trace], innermost first, as `file function`.
List<String> claudartFrames(StackTrace trace) {
  final frame = RegExp(r'#\d+\s+(.+?) \(package:claudart/([^:]+):\d+:\d+\)');
  return [
    for (final match in frame.allMatches(trace.toString()))
      '${match.group(2)} ${match.group(1)}',
  ];
}

int _archiveFiles(MemoryFileIO io) {
  final prefix = archiveDirFor(_workspace);
  return io.files.keys.where((path) => path.startsWith(prefix)).length;
}

String _statusOf(MemoryFileIO io) {
  final text = io.read(handoffPathFor(_workspace));
  return SessionState.parse(text).effectiveStatus.name;
}

Future<T> _quiet<T>(Future<T> Function() body) => runZoned(
      body,
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );

Never _throwExit(int code) => throw StateError('exit $code');

PipelineExecutor _executor(String planText) => PipelineExecutor(
      prompter: unscriptedUserPrompter,
      approvalSelector: unscriptedApprovalSelector,
      runner: ({
        required model,
        required systemPrompt,
        required message,
        required workingDir,
        required allowedTools,
        required helperModel,
        StepMode mode = StepMode.project,
      }) async =>
          StepResult(
        text: planText,
        usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
      ),
    );

String _readyHandoff({List<String>? pending}) {
  var content = handoffTemplate(
    branch: 'main',
    date: '2026-01-01',
    bug: 'The parser drops a line.',
    expected: 'It keeps every line.',
    projectName: ProjectFixture.name,
    pendingIssues: pending,
  );
  content = updateSection(content, 'Root Cause', 'The splitter stops early.');
  content = updateSection(
    content,
    'Scope',
    '### Files in play\n- `lib/foo.dart`\n\n### Must not touch\nnothing',
  );
  return withHandoffStatus(content, HandoffStatus.readyForDebug);
}

MemoryFileIO _io(String projectRoot, {String? config, List<String>? pending}) {
  final io = MemoryFileIO(files: {
    handoffPathFor(_workspace): _readyHandoff(pending: pending),
  });
  Registry.empty()
      .add(RegistryEntry(
        name: ProjectFixture.name,
        projectRoot: projectRoot,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-01-01',
      ))
      .save(io: io);
  if (config != null) io.write(configPathFor(_workspace), config);
  return io;
}

/// `debug`, with [verificationCommand] configured or not, and a gate that
/// [passes] or not.
Future<GateRun> debugRun({
  required String useCase,
  String? verificationCommand,
  bool passes = true,
}) async {
  final root = Directory.systemTemp.createTempSync('gate_topology_debug_');
  try {
    final io = _io(
      root.path,
      config: verificationCommand == null
          ? null
          : jsonEncode({'verificationCommand': verificationCommand}),
    );
    final plan = '${WireTag.editFile.openPrefix} path="lib/foo.dart">\n'
        'void a() {}\n${WireTag.editFile.close}';
    var invoked = false;
    String? shell;
    AtGate? atGate;
    var chain = <String>[];
    var result = 'returned';
    try {
      await _quiet(() => runDebug(
            seams: CommandSeams(
              io: io,
              projectRootOverride: root.path,
              exitFn: _throwExit,
              pickFn: (_) => 0,
            ),
            executor: _executor(plan),
            dartFileAnalyzer: (_, __) => true,
            runVerification: (command, projectRoot) {
              invoked = true;
              shell = command;
              chain = claudartFrames(StackTrace.current);
              atGate = (
                status: _statusOf(io),
                archiveFiles: _archiveFiles(io),
                fixWritten: File(p.join(root.path, 'lib/foo.dart')).existsSync(),
              );
              return passes;
            },
          ));
    } on EditPlanException catch (e) {
      result = 'threw ${e.failure.name}';
    }
    return (
      command: 'debug',
      useCase: useCase,
      configKey: 'verificationCommand',
      invoked: invoked,
      shellCommand: shell,
      atGate: atGate,
      callChain: chain,
      result: result,
      moves: [for (final move in loggedMoves(io, _workspace)) '${move['event']}'],
      statusAfter: _statusOf(io),
      archiveFilesAfter: _archiveFiles(io),
      fixLeftWritten: File(p.join(root.path, 'lib/foo.dart')).existsSync(),
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// `rotate` with a gate that [passes] or not, and [pending] issues to seed.
Future<GateRun> rotateRun({
  required String useCase,
  bool passes = true,
  List<String>? pending,
}) async {
  final io = _io(ProjectFixture.root, pending: pending);
  var invoked = false;
  String? shell;
  AtGate? atGate;
  var chain = <String>[];
  final outcome = await _quiet(() => runRotate(
        seams: CommandSeams(
          io: io,
          projectRootOverride: ProjectFixture.root,
          exitFn: _throwExit,
          confirmFn: (_) => true,
        ),
        mode: RunMode.headless,
        buildFn: (command) async {
          invoked = true;
          shell = command;
          chain = claudartFrames(StackTrace.current);
          atGate = (
            status: _statusOf(io),
            archiveFiles: _archiveFiles(io),
            fixWritten: false,
          );
          return passes;
        },
      ));
  return (
    command: 'rotate',
    useCase: useCase,
    configKey: 'afterFixCommand',
    invoked: invoked,
    shellCommand: shell,
    atGate: atGate,
    callChain: chain,
    result: 'returned ${outcome.name}',
    moves: [for (final move in loggedMoves(io, _workspace)) '${move['event']}'],
    statusAfter: _statusOf(io),
    archiveFilesAfter: _archiveFiles(io),
    fixLeftWritten: false,
  );
}

String _cell(Object? value) => '$value'.replaceAll('|', r'\|');

String renderGates(List<GateRun> runs, {required Set<String> sharingShell}) {
  String row(GateRun run) {
    final at = run.atGate;
    return '| ${run.command} | ${run.useCase} | `${run.configKey}` | '
        '${run.invoked ? '`${_cell(run.shellCommand)}`' : 'not run'} | '
        '${at == null ? '—' : '${at.status}; archive ${at.archiveFiles}; fix '
            '${at.fixWritten ? 'written' : '—'}'} | '
        '${_cell(run.result)} | ${run.moves.isEmpty ? '—' : run.moves.join(', ')}'
        ' | ${run.statusAfter}; archive ${run.archiveFilesAfter}; fix '
        '${run.fixLeftWritten ? 'kept' : '—'} |';
  }

  final chains = {
    for (final run in runs)
      if (run.invoked) '${run.command} / ${run.useCase}': run.callChain,
  };
  return [
    '# The two gates, run',
    '',
    '> Generated by `make topology` from real runs of `debug` and `rotate`. Do '
        'not edit by hand: a test fails when this file and the code disagree.',
    '',
    '`debug` runs `verificationCommand` and `rotate` runs `afterFixCommand`. '
        'Each use case below is run through the command; the columns say what '
        'existed when the gate ran and what was left after.',
    '',
    '| command | use case | config key | shell command | at the gate | result | '
        'moves logged | after |',
    '|---|---|---|---|---|---|---|---|',
    for (final run in runs) row(run),
    '',
    '## Call chain to the gate (claudart frames, innermost first)',
    '',
    for (final entry in chains.entries) ...[
      '- **${entry.key}**: ${entry.value.join(' ← ')}',
    ],
    '',
    '## Code that spells the shell invocation',
    '',
    'Files naming `shellExecutable`: ${sharingShell.toList().join(', ')}.',
    '',
  ].join('\n');
}

Set<String> _filesNamingShell() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (file.readAsStringSync().contains('shellExecutable') &&
            !file.path.endsWith('process_runner.dart'))
          file.path,
    };

void main() {
  group('the two gates, use case by use case', () {
    late List<GateRun> runs;
    setUpAll(() async {
      runs = [
        await debugRun(useCase: 'no command configured'),
        await debugRun(
          useCase: 'command configured, passes',
          verificationCommand: 'dart test',
        ),
        await debugRun(
          useCase: 'command configured, fails',
          verificationCommand: 'dart test',
          passes: false,
        ),
        await rotateRun(
          useCase: 'passes, a pending issue to seed',
          pending: ['second issue'],
        ),
        await rotateRun(
          useCase: 'fails, a pending issue to seed',
          passes: false,
          pending: ['second issue'],
        ),
        await rotateRun(useCase: 'passes, nothing pending'),
      ];
    });

    GateRun run(String command, String useCase) => runs
        .singleWhere((r) => r.command == command && r.useCase == useCase);

    test('debug with no command configured never runs a gate', () {
      final r = run('debug', 'no command configured');
      expect(r.invoked, isFalse);
      expect(r.statusAfter, HandoffStatus.debugComplete.name);
    });

    test('debug runs its gate after the fix is written, before fixApplied', () {
      final r = run('debug', 'command configured, passes');
      expect(r.atGate!.fixWritten, isTrue);
      expect(r.atGate!.status, HandoffStatus.debugInProgress.name);
      expect(r.moves, ['debugStarted', 'fixApplied']);
    });

    test('a failing debug gate restores the fix and blocks the session', () {
      final r = run('debug', 'command configured, fails');
      expect(r.result, 'threw ${FailureType.fixVerificationFailed.name}');
      expect(r.fixLeftWritten, isFalse);
      expect(r.statusAfter, HandoffStatus.needsSuggest.name);
      expect(r.moves, ['debugStarted', 'debugBlocked']);
    });

    test('rotate runs its gate after the archive is written, before the '
        'handoff changes', () {
      final r = run('rotate', 'passes, a pending issue to seed');
      expect(r.atGate!.archiveFiles, greaterThan(0));
      expect(r.atGate!.status, HandoffStatus.readyForDebug.name);
      expect(r.moves, ['rotated']);
    });

    test('a failing rotate gate keeps the archive and leaves the handoff '
        'alone, and logs no move', () {
      final r = run('rotate', 'fails, a pending issue to seed');
      expect(r.result, 'returned buildFailed');
      expect(r.archiveFilesAfter, greaterThan(0));
      expect(r.statusAfter, HandoffStatus.readyForDebug.name);
      expect(r.moves, isEmpty);
    });

    test('rotate runs its gate even when nothing is pending', () {
      final r = run('rotate', 'passes, nothing pending');
      expect(r.invoked, isTrue);
      expect(r.moves, ['rotatedEmpty']);
    });

    test('both gates run a command read from a different config key', () {
      expect(run('debug', 'command configured, passes').configKey,
          isNot(run('rotate', 'passes, nothing pending').configKey));
    });

    test('rotate reads the default afterFixCommand when none is set', () {
      expect(run('rotate', 'passes, nothing pending').shellCommand,
          'make rebuild');
    });

    test('a rotate whose gate fails archives again each time it is retried',
        () async {
      final io = _io(ProjectFixture.root, pending: ['second issue']);
      Future<void> failingRotate() => _quiet(() => runRotate(
            seams: CommandSeams(
              io: io,
              projectRootOverride: ProjectFixture.root,
              exitFn: _throwExit,
              confirmFn: (_) => true,
            ),
            mode: RunMode.headless,
            buildFn: (_) async => false,
          ));
      int entries() => (jsonDecode(io.read(p.join(archiveDirFor(_workspace), archiveIndexFileName)))
              as List<dynamic>)
          .length;
      await failingRotate();
      final afterFirst = entries();
      await failingRotate();
      expect(afterFirst, 1);
      expect(entries(), 2, reason: 'the handoff did not change, the archive grew');
      expect(_statusOf(io), HandoffStatus.readyForDebug.name);
    });

    test('a failing gate leaves no log row naming its command or its output',
        () async {
      final io = _io(ProjectFixture.root, pending: ['second issue']);
      await _quiet(() => runRotate(
            seams: CommandSeams(
              io: io,
              projectRootOverride: ProjectFixture.root,
              exitFn: _throwExit,
              confirmFn: (_) => true,
            ),
            mode: RunMode.headless,
            buildFn: (_) async => false,
          ));
      final logged = [
        for (final entry in io.files.entries)
          if (entry.key.startsWith(logsDirFor(_workspace))) entry.value,
      ].join('\n');
      expect(logged, isNot(contains('make rebuild')));
      expect(logged, isNot(contains('exit')));
    });

    test('both spell the shell invocation through the same constants', () {
      expect(
        _filesNamingShell(),
        containsAll(['lib/commands/debug.dart', 'lib/commands/rotate.dart']),
      );
    });

    test('the call chain of each gate is captured from the claudart frames',
        () {
      for (final r in runs.where((r) => r.invoked)) {
        expect(r.callChain, isNotEmpty, reason: '${r.command} ${r.useCase}');
      }
    });

    test('the checked-in doc matches the runs', () {
      final doc = renderGates(runs, sharingShell: _filesNamingShell());
      if (Platform.environment[_updateEnvVar] == _updateEnabledValue) {
        File(_docPath).writeAsStringSync(doc);
      }
      expect(File(_docPath).readAsStringSync(), doc);
    });
  });

  group('claudartFrames', () {
    test('keeps only claudart frames, as file and function', () {
      const trace = '#0      foo (package:other/x.dart:1:2)\n'
          '#1      runX.<fn> (package:claudart/commands/x.dart:10:5)\n'
          '#2      bar (package:claudart/io/y.dart:3:4)\n';
      expect(claudartFrames(StackTrace.fromString(trace)), [
        'commands/x.dart runX.<fn>',
        'io/y.dart bar',
      ]);
    });
  });
}
