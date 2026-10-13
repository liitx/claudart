import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/commands/debug.dart';
import 'package:claudart/md_io.dart' show readHandoffStatus, withHandoffStatus;
import 'package:claudart/registry.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import '../helpers/logged_moves.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';
import '../helpers/variant_topology.dart';

// debug_test.dart — coverage for runDebug.
//
// Companion to suggest_test.dart. Covers: registration/handoff/scope
// validation exits; the status gate, one case per persisted status, expected
// from HandoffStatus.after(fixApplied) (a rejected status throws before any
// model call); the reader-step-produces-nothing path; and the approve/exit
// choice past a successful implementer step, asserting the written status.
// Interaction seams that a test does not script are the throwing
// `unscripted*` helpers, so a regression fails instead of blocking on stdin.

const _projectRoot = '/projects/my-app';
const _workspace   = '/workspaces/my-app';

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

MemoryFileIO _io({String? handoff = _handoffReadyWithScope}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
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
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project}) async => null);

/// Answers every step with a plan that has CHANGES but no EDIT_FILE tags:
/// drives the happy path to the handoff write without touching real disk.
HandoffStatus _statusOf(MemoryFileIO io) =>
    readHandoffStatus(io.read(handoffPathFor(_workspace)));

/// [onCall] counts model calls, so a test can prove none were spent.
PipelineExecutor _executorWithPlan({void Function()? onCall}) =>
    PipelineExecutor(
      runner: ({
        required model,
        required systemPrompt,
        required message,
        required workingDir,
        StepMode mode = StepMode.project,
      }) async {
        onCall?.call();
        return const StepResult(
          text: '<CHANGES>no file edits needed</CHANGES>',
          usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
        );
      },
    );

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

    test('handoff is left untouched — no partial write on reader failure', () async {
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
      expect(io.read(handoffPathFor(_workspace)), equals(_handoffReadyWithScope));
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

    test('logs the transition it applied: command, from, event, to', () async {
      final io = _io();
      await runDebug(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        executor: _executorWithPlan(),
        pickFn: (_) => 0,
      );
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.debug.name,
          'from': HandoffStatus.readyForDebug.name,
          'event': HandoffEvent.fixApplied.name,
          'to': HandoffStatus.debugComplete.name,
        },
      ]);
    });

    test('choosing exit leaves the status readyForDebug', () async {
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
      expect(_statusOf(io), HandoffStatus.readyForDebug);
    });
  });
}
