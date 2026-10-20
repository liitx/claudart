import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/commands/debug.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/md_io.dart' show readHandoffStatus, withHandoffStatus;
import 'package:claudart/registry.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/edit_files.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/pipeline/xml_tags.dart';
import '../helpers/logged_moves.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';
import '../helpers/variant_topology.dart';
import 'package:claudart/logging/log_file.dart';
import '../helpers/project_fixture.dart';

// debug_test.dart — coverage for runDebug.
//
// Companion to suggest_test.dart. Covers: registration/handoff/scope
// validation exits; the status gate, one case per persisted status, expected
// from HandoffStatus.after(fixApplied) (a rejected status throws before any
// model call); the reader-step-produces-nothing path; and the approve/exit
// choice past a successful implementer step, asserting the written status.
// Interaction seams that a test does not script are the throwing
// `unscripted*` helpers, so a regression fails instead of blocking on stdin.

const _projectRoot = ProjectFixture.root;
const _workspace   = ProjectFixture.workspace;

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

const _handoffReadyWithScope = '''# Agent Handoff — my-app

## Status

ready-for-debug

## Bug

Something is broken.

## Root Cause

Found it.

## Scope

### Files in play
- `lib/foo.dart`
''';

const _handoffReadyWithoutScope = '''# Agent Handoff — my-app

## Status

ready-for-debug

## Bug

Something is broken.

## Scope

### Files in play
_Not yet determined._
''';

MemoryFileIO _io({
  String? handoff = _handoffReadyWithScope,
  String projectRoot = _projectRoot,
}) {
  final entry = RegistryEntry(
    name: 'my-app',
    projectRoot: projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final registry = Registry.empty().add(entry);
  final io = MemoryFileIO(
    files: {
      if (handoff != null) handoffPathFor(_workspace): handoff,
    },
  );
  registry.save(io: io);
  return io;
}

PipelineExecutor _executorWithNoOutput() =>
    PipelineExecutor(
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
          null,
    );

/// Answers every step with a plan that has CHANGES but no EDIT_FILE tags:
/// drives the happy path to the handoff write without touching real disk.
HandoffStatus _statusOf(MemoryFileIO io) =>
    readHandoffStatus(io.read(handoffPathFor(_workspace)));

PipelineExecutor _executorWithPlanText(String text) => PipelineExecutor(
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
            text: text,
            usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
          ),
    );

/// [onCall] counts model calls, so a test can prove none were spent.
PipelineExecutor _executorWithPlan({void Function()? onCall}) =>
    PipelineExecutor(
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
      }) async {
        onCall?.call();
        return const StepResult(
          text: '<CHANGES>no file edits needed</CHANGES>',
          usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
        );
      },
    );

Map<String, String> _move(
  HandoffStatus from,
  HandoffEvent event,
  HandoffStatus to,
) =>
    {
      'command': ClaudartCommand.debug.name,
      'from': from.name,
      'event': event.name,
      'to': to.name,
    };

void main() {
  group('runDebug — validation', () {
    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO();
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when no handoff exists', () async {
      final io = _io(handoff: null);
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when Scope / Files in play is empty', () async {
      final io = _io(handoff: _handoffReadyWithoutScope);
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('runDebug — reader step produces nothing', () {
    test('exits 1 without reaching the interactive review loop', () async {
      final io = _io();
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
          executor: _executorWithNoOutput(),
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('a failed step blocks the session: needsSuggest', () async {
      final io = _io();
      try {
        await runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
          executor: _executorWithNoOutput(),
        );
      } on _ExitException {
        // expected
      }
      expect(_statusOf(io), HandoffStatus.needsSuggest);
      expect(loggedMoves(io, _workspace), [
        _move(
          HandoffStatus.readyForDebug,
          HandoffEvent.debugStarted,
          HandoffStatus.debugInProgress,
        ),
        _move(
          HandoffStatus.debugInProgress,
          HandoffEvent.debugBlocked,
          HandoffStatus.needsSuggest,
        ),
      ]);
    });

    test('tells the owner to check the CLI when the reader gives nothing',
        () async {
      final output = <String>[];
      try {
        await runZoned(
          () => runDebug(
            io: _io(),
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            pickFn: unscriptedPick,
            executor: _executorWithNoOutput(),
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        );
      } on _ExitException {
        // expected
      }
      expect(
        output.join('\n'),
        contains('Is claude CLI installed and authenticated?'),
      );
    });

    test('an implementer that produces nothing blocks the session', () async {
      final io = _io();
      // Haiku classifies and reads, so it answers; the implementer (sonnet or
      // opus) answers with nothing.
      final executor = PipelineExecutor(
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
              text: model == AgentModel.haiku ? 'file contents' : '',
              usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
            ),
      );
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: unscriptedPick,
          executor: executor,
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(_statusOf(io), HandoffStatus.needsSuggest);
      expect(loggedMoves(io, _workspace), [
        _move(
          HandoffStatus.readyForDebug,
          HandoffEvent.debugStarted,
          HandoffStatus.debugInProgress,
        ),
        _move(
          HandoffStatus.debugInProgress,
          HandoffEvent.debugBlocked,
          HandoffStatus.needsSuggest,
        ),
      ]);
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      try {
        await runZoned(
          () => runDebug(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
              pickFn: unscriptedPick,
            executor: _executorWithNoOutput(),
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        );
      } on _ExitException {
        // expected
      }
      expect(output.join('\n'), contains('Project  : my-app'));
    });
  });

  group('runDebug — status gate follows HandoffStatus.after', () {
    final accepted = topologyOf(
      HandoffStatus.values,
      (s) => s.after(HandoffEvent.fixApplied) != null,
    );

    for (final status in HandoffStatus.values.where((s) => s.isPersisted)) {
      final runs = accepted[status]!;
      final outcome = runs ? 'runs to debugComplete' : 'is rejected';
      test('${status.name}: $outcome', () async {
        final io = _io(
          handoff: withHandoffStatus(_handoffReadyWithScope, status),
        );
        var modelCalls = 0;
        final run = runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          executor: _executorWithPlan(onCall: () => modelCalls++),
          pickFn: (_) => 0,
        );
        if (runs) {
          await run;
          expect(_statusOf(io), HandoffStatus.debugComplete);
        } else {
          await expectLater(
            run,
            throwsA(isA<InvalidHandoffTransitionException>()),
          );
          expect(modelCalls, 0, reason: 'rejected before any model call');
          expect(_statusOf(io), status);
          expect(loggedMoves(io, _workspace), isEmpty);
        }
      });
    }
  });

  group('runDebug — applied plan', () {
    test('moves the handoff from readyForDebug to debugComplete', () async {
      final io = _io();
      expect(_statusOf(io), HandoffStatus.readyForDebug);

      await runDebug(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        executor: _executorWithPlan(),
        pickFn: (_) => 0,
      );

      expect(_statusOf(io), HandoffStatus.debugComplete);
    });

    test('logs the transitions it applied: command, from, event, to', () async {
      final io = _io();
      await runDebug(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        executor: _executorWithPlan(),
        pickFn: (_) => 0,
      );
      expect(loggedMoves(io, _workspace), [
        _move(
          HandoffStatus.readyForDebug,
          HandoffEvent.debugStarted,
          HandoffStatus.debugInProgress,
        ),
        _move(
          HandoffStatus.debugInProgress,
          HandoffEvent.fixApplied,
          HandoffStatus.debugComplete,
        ),
      ]);
    });

    test('choosing exit leaves the status debugInProgress', () async {
      final io = _io();
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          executor: _executorWithPlan(),
          pickFn: (_) => 1,
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(_statusOf(io), HandoffStatus.debugInProgress);
    });
  });

  // The review prints before anything is written: the plan's summary, then one
  // line per planned file, labeled by whether the file already exists.
  group('runDebug — review of the plan', () {
    const summary = 'the review summary';
    const path = 'lib/foo.dart';
    const changes = WireTag.changes;
    const editFile = WireTag.editFile;
    final plan = '${changes.openPrefix}>$summary${changes.close}\n'
        '${editFile.openPrefix} path="$path">\nvoid a() {}\n${editFile.close}';

    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('claudart_review_'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<String> reviewOutput() async {
      final output = <String>[];
      try {
        await runZoned(
          () => runDebug(
            io: _io(projectRoot: root.path),
            projectRootOverride: root.path,
            exitFn: _throwExit,
            executor: _executorWithPlanText(plan),
            pickFn: (_) => 1,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        );
      } on _ExitException {
        // choosing exit ends the run after the review is printed
      }
      return output.join('\n');
    }

    test('prints the CHANGES text of the plan', () async {
      expect(await reviewOutput(), contains(summary));
    });

    // The later divider is 44 wide and the files underline 13, so a line of
    // exactly 38 is the one above the total.
    test('prints the usage total under a divider', () async {
      final output = await reviewOutput();
      final lines = [
        for (final line in output.split('\n'))
          line.replaceAll(RegExp('\x1B\\[[0-9;]*m'), '').trim(),
      ];
      expect(lines, contains('─' * 38));
      expect(output, contains('Total'));
    });

    test('labels a file that does not exist NEW', () async {
      final output = await reviewOutput();
      expect(output, contains('NEW'));
      expect(output, isNot(contains('MOD')));
      expect(output, contains(path));
    });

    test('labels a file that already exists MOD', () async {
      File('${root.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old');
      final output = await reviewOutput();
      expect(output, contains('MOD'));
      expect(output, isNot(contains('NEW')));
    });
  });

  // A malformed plan blocks the apply path: the typed failure surfaces, the
  // session is blocked (debugBlocked) before any fix event, and the plan is
  // parsed before any of the review prints.
  group('runDebug — malformed plan', () {
    final truncatedPlan =
        '${WireTag.editFile.openPrefix} path="lib/foo.dart">\ncut off';

    test('an unterminated block blocks the session', () async {
      final io = _io();
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          executor: _executorWithPlanText(truncatedPlan),
          pickFn: (_) => 0,
        ),
        throwsA(
          isA<EditPlanException>().having(
            (e) => e.failure,
            'failure',
            FailureType.editPlanMalformed,
          ),
        ),
      );
      expect(_statusOf(io), HandoffStatus.needsSuggest);
      expect(loggedMoves(io, _workspace), [
        _move(
          HandoffStatus.readyForDebug,
          HandoffEvent.debugStarted,
          HandoffStatus.debugInProgress,
        ),
        _move(
          HandoffStatus.debugInProgress,
          HandoffEvent.debugBlocked,
          HandoffStatus.needsSuggest,
        ),
      ]);
    });

    test('prints none of the review', () async {
      final output = <String>[];
      await expectLater(
        runZoned(
          () => runDebug(
            io: _io(),
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            executor: _executorWithPlanText(truncatedPlan),
            pickFn: (_) => 0,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        ),
        throwsA(isA<EditPlanException>()),
      );
      expect(output.join('\n'), isNot(contains('──────')));
    });
  });

  // A plan that parses but fails verification restores the files, blocks the
  // session and never records fixApplied.
  group('runDebug — failed verification', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('claudart_verify_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('restores the files and blocks the session', () async {
      final io = _io(projectRoot: root.path);
      final plan = '${WireTag.editFile.openPrefix} path="lib/foo.dart">\n'
          'void a() {}\n${WireTag.editFile.close}';
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: root.path,
          exitFn: _throwExit,
          executor: _executorWithPlanText(plan),
          pickFn: (_) => 0,
          dartFileAnalyzer: (_, __) => false,
        ),
        throwsA(
          isA<EditPlanException>().having(
            (e) => e.failure,
            'failure',
            FailureType.editVerificationFailed,
          ),
        ),
      );
      expect(File('${root.path}/lib/foo.dart').existsSync(), isFalse);
      expect(_statusOf(io), HandoffStatus.needsSuggest);
      expect(
        loggedMoves(io, _workspace).map((move) => move['event']),
        [HandoffEvent.debugStarted.name, HandoffEvent.debugBlocked.name],
      );
    });
  });

  // Every way a debug run can end is one DebugExitKind, and each one is logged
  // as the outcome of the run, so a run that stopped leaves a record of why.
  group('$DebugExitKind', () {
    const exitCodeByKind = <DebugExitKind, int>{
      DebugExitKind.notInGitRepository: 1,
      DebugExitKind.projectNotRegistered: 1,
      DebugExitKind.noHandoff: 1,
      DebugExitKind.emptyScope: 1,
      DebugExitKind.readerProducedNothing: 1,
      DebugExitKind.implementerProducedNothing: 1,
      DebugExitKind.ownerDeclinedWrite: 0,
    };
    for (final kind in DebugExitKind.values) {
      test('${kind.name} exits with ${exitCodeByKind[kind]}', () {
        expect(kind.exitCode, exitCodeByKind[kind]);
      });
    }
  });

  group('runDebug — every exit is logged', () {
    List<String> outcomes(MemoryFileIO io, String logsDir) {
      final raw = io.read(logFilePath(logsDir, LogFile.interactions));
      return [
        for (final line in raw.split('\n'))
          if (line.isNotEmpty)
            (jsonDecode(line) as Map<String, dynamic>)['outcome'] as String,
      ];
    }

    Future<void> endedBy(
      MemoryFileIO io, {
      PipelineExecutor? executor,
      int Function(List<String>)? pickFn,
    }) async {
      try {
        await runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          pickFn: pickFn ?? unscriptedPick,
          executor: executor,
        );
      } on _ExitException {
        // every scenario here ends in an exit
      }
    }

    PipelineExecutor haikuAnswersImplementerSilent() => PipelineExecutor(
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
                text: model == AgentModel.haiku ? 'file contents' : '',
                usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
              ),
        );

    // Each scenario ends the run one way and names where its log is written:
    // before a project is known there is no workspace, so the global one.
    final scenarios = <DebugExitKind, Future<List<String>> Function()>{
      DebugExitKind.projectNotRegistered: () async {
        final io = MemoryFileIO();
        await endedBy(io);
        return outcomes(io, p.join(claudeDir, 'logs'));
      },
      DebugExitKind.noHandoff: () async {
        final io = _io(handoff: null);
        await endedBy(io);
        return outcomes(io, logsDirFor(_workspace));
      },
      DebugExitKind.emptyScope: () async {
        final io = _io(handoff: _handoffReadyWithoutScope);
        await endedBy(io);
        return outcomes(io, logsDirFor(_workspace));
      },
      DebugExitKind.readerProducedNothing: () async {
        final io = _io();
        await endedBy(io, executor: _executorWithNoOutput());
        return outcomes(io, logsDirFor(_workspace));
      },
      DebugExitKind.implementerProducedNothing: () async {
        final io = _io();
        await endedBy(io, executor: haikuAnswersImplementerSilent());
        return outcomes(io, logsDirFor(_workspace));
      },
      DebugExitKind.ownerDeclinedWrite: () async {
        final io = _io();
        await endedBy(
          io,
          executor: _executorWithPlan(),
          pickFn: (_) => 1,
        );
        return outcomes(io, logsDirFor(_workspace));
      },
    };

    // Not being inside a git repository cannot be reached from a test without
    // changing the process's working directory, which every parallel test
    // shares, so only its exit code is pinned above.
    test('every other kind has a scenario here', () {
      expect(
        {...scenarios.keys, DebugExitKind.notInGitRepository},
        DebugExitKind.values.toSet(),
      );
    });

    scenarios.forEach((kind, scenario) {
      test('${kind.name} is logged as the outcome', () async {
        expect(await scenario(), contains(kind.name));
      });
    });
  });
}
