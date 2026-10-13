import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/debug.dart';
import 'package:claudart/md_io.dart' show readHandoffStatus, withHandoffStatus;
import 'package:claudart/registry.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import '../helpers/mocks.dart';

// debug_test.dart — validation-path coverage for runDebug.
//
// Companion to suggest_test.dart. Covers: registration/handoff/scope
// validation exits, the status-confirmation gate (now injectable via
// confirmFn — previously hardcoded stdin.readLineSync()), and the
// reader-step-produces-nothing path via an injected PipelineExecutor.
//
// Not covered: the review/apply menu past a successful implementer step
// (pickFn is injectable now, but reaching that point needs a full fake
// PipelineExecutor round-trip through both reader and implementer steps
// with realistic EDIT_FILE-tagged output — out of scope for this pass).

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

const _handoffNotReady = '''# Agent Handoff — my-app

## Status

suggest-investigating

## Bug

Something is broken.

## Scope

### Files in play
- `lib/foo.dart`
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
PipelineExecutor _executorWithPlan() => PipelineExecutor(
      runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project}) async =>
          const StepResult(
            text: '<CHANGES>no file edits needed</CHANGES>',
            usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
          ),
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
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('runDebug — status confirmation gate', () {
    test('status != ready-for-debug: confirming "no" aborts with exit 0', () async {
      final io = _io(handoff: _handoffNotReady);
      var askedQuestion = '';
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: (q) {
            askedQuestion = q;
            return false;
          },
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(0))),
      );
      expect(askedQuestion, equals('Run debug anyway?'));
    });

    test('status != ready-for-debug: confirming "yes" proceeds past the gate', () async {
      final io = _io(handoff: _handoffNotReady);
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: (_) => true,
          executor: _executorWithNoOutput(),
        ),
        // Proceeds past the gate, then hits the reader-produces-nothing
        // exit(1) — proving the gate itself did not block.
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(1))),
      );
    });

    test('status is already ready-for-debug: gate is skipped entirely', () async {
      final io = _io();
      var confirmWasCalled = false;
      await expectLater(
        runDebug(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: (_) {
            confirmWasCalled = true;
            return true;
          },
          executor: _executorWithNoOutput(),
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(confirmWasCalled, isFalse);
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

  group('runDebug — status gate, one case per persisted status', () {
    for (final status in HandoffStatus.values.where((s) => s.isPersisted)) {
      final asked = status != HandoffStatus.readyForDebug;
      test('${status.name}: confirm is ${asked ? 'asked' : 'skipped'}', () async {
        final io = _io(handoff: withHandoffStatus(_handoffReadyWithScope, status));
        var confirmCalls = 0;
        await expectLater(
          runDebug(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            confirmFn: (_) {
              confirmCalls++;
              return true;
            },
            executor: _executorWithNoOutput(),
          ),
          throwsA(isA<_ExitException>()),
        );
        expect(confirmCalls, asked ? 1 : 0);
      });
    }
  });

  group('runDebug — applied plan', () {
    test('moves the handoff from readyForDebug to debugComplete', () async {
      final io = _io();
      expect(readHandoffStatus(io.read(handoffPathFor(_workspace))), HandoffStatus.readyForDebug);

      await runDebug(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        executor: _executorWithPlan(),
        pickFn: (_) => 0,
      );

      expect(readHandoffStatus(io.read(handoffPathFor(_workspace))), HandoffStatus.debugComplete);
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
      expect(readHandoffStatus(io.read(handoffPathFor(_workspace))), HandoffStatus.readyForDebug);
    });
  });
}
