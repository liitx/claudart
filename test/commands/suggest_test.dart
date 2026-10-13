import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/commands/suggest.dart';
import 'package:claudart/md_io.dart'
    show readHandoffStatus, readSection, withHandoffStatus;
import 'package:claudart/registry.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/pipeline/step_mode.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';
import '../helpers/variant_topology.dart';

// suggest_test.dart — validation-path coverage for runSuggest.
//
// Scope: runSuggest has injectable confirmFn/promptFn/pickFn seams
// (matching setup.dart's pattern), so stdin/arrowMenu aren't the blocker.
// The remaining gap is a realistic PipelineExecutor output to drive the
// approve/refine loop — full coverage of that loop needs a fixture for
// that, not an injection seam; this covers what's safely testable today.

const _projectRoot = '/projects/my-app';
const _workspace   = '/workspaces/my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

const _handoffWithScope = '''# Agent Handoff — my-app

## Status

suggest-investigating

## Bug

Something is broken.

## Expected Behavior

It should work.

## Scope

### Files in play
- `lib/foo.dart`
''';

const _handoffWithoutScope = '''# Agent Handoff — my-app

## Status

suggest-investigating

## Bug

Something is broken.

## Expected Behavior

It should work.

## Scope

### Files in play
_Not yet determined._
''';

MemoryFileIO _io({String? handoff = _handoffWithScope}) {
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

/// Executor whose runner always returns null — simulates the reader step
/// producing nothing (e.g. claude CLI not installed/authenticated),
/// without ever reaching the interactive review loop.
PipelineExecutor _executorWithNoOutput() =>
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project}) async => null);

const _rootCause = 'Off-by-one in foo()';

/// The transitions a command logged, minus the timestamp.
List<Map<String, dynamic>> _loggedTransitions(MemoryFileIO io) {
  final raw = io.read(p.join(logsDirFor(_workspace), 'transitions.jsonl'));
  return [
    for (final line in raw.split('\n').where((l) => l.isNotEmpty))
      {...jsonDecode(line) as Map<String, dynamic>}..remove('ts'),
  ];
}

HandoffStatus _statusOf(MemoryFileIO io) =>
    readHandoffStatus(io.read(handoffPathFor(_workspace)));

/// Executor whose runner answers every step with one analysis carrying every
/// tag the writer reads — drives the happy path through to the handoff write.
/// [onCall] counts model calls, so a test can prove none were spent.
PipelineExecutor _executorWithAnalysis({void Function()? onCall}) =>
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
          text: '<ROOT_CAUSE>$_rootCause</ROOT_CAUSE>'
              '<SCOPE_FILES>- `lib/foo.dart`</SCOPE_FILES>'
              '<SCOPE_ENTRIES>foo()</SCOPE_ENTRIES>'
              '<SCOPE_CLASSES>Foo</SCOPE_CLASSES>'
              '<MUST_NOT_TOUCH>lib/bar.dart</MUST_NOT_TOUCH>'
              '<CONSTRAINTS>keep API</CONSTRAINTS>',
          usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
        );
      },
    );

void main() {
  group('runSuggest — validation', () {
    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO(); // empty registry
      await expectLater(
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when no handoff exists', () async {
      final io = _io(handoff: null);
      await expectLater(
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits 1 when Scope / Files in play is empty', () async {
      final io = _io(handoff: _handoffWithoutScope);
      await expectLater(
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          pickFn: unscriptedPick,
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('runSuggest — reader step produces nothing', () {
    test('exits 1 without reaching the interactive review loop', () async {
      final io = _io();
      await expectLater(
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          pickFn: unscriptedPick,
          executor: _executorWithNoOutput(),
        ),
        throwsA(isA<_ExitException>()),
      );
    });

    test('handoff is left untouched — no partial write on reader failure', () async {
      final io = _io();
      try {
        await runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          pickFn: unscriptedPick,
          executor: _executorWithNoOutput(),
        );
      } on _ExitException {
        // expected
      }
      expect(io.read(handoffPathFor(_workspace)), equals(_handoffWithScope));
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      try {
        await runZoned(
          () => runSuggest(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            confirmFn: unscriptedConfirm,
            promptFn: unscriptedPrompt,
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

  group('runSuggest — approved findings', () {
    test('approving moves suggestInvestigating to readyForDebug and keeps the '
        'root cause', () async {
      final io = _io();
      expect(_statusOf(io), HandoffStatus.suggestInvestigating);

      await runSuggest(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        confirmFn: unscriptedConfirm,
        promptFn: unscriptedPrompt,
        executor: _executorWithAnalysis(),
        pickFn: (_) => 0,
      );

      final written = io.read(handoffPathFor(_workspace));
      expect(readHandoffStatus(written), HandoffStatus.readyForDebug);
      expect(readSection(written, 'Root Cause'), _rootCause);
    });

    test('logs the transition it applied: command, from, event, to', () async {
      final io = _io();
      await runSuggest(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
        executor: _executorWithAnalysis(),
        pickFn: (_) => 0,
      );
      expect(_loggedTransitions(io), [
        {
          'command': ClaudartCommand.suggest.name,
          'from': HandoffStatus.suggestInvestigating.name,
          'event': HandoffEvent.saveConfirmedReady.name,
          'to': HandoffStatus.readyForDebug.name,
        },
      ]);
    });

    test('choosing exit leaves the status untouched', () async {
      final io = _io();
      await expectLater(
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          confirmFn: unscriptedConfirm,
          promptFn: unscriptedPrompt,
          executor: _executorWithAnalysis(),
          pickFn: (_) => 2,
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(_statusOf(io), HandoffStatus.suggestInvestigating);
    });
  });

  group('runSuggest — status gate follows HandoffStatus.after', () {
    final accepted = topologyOf(
      HandoffStatus.values,
      (s) => s.after(HandoffEvent.saveConfirmedReady) != null,
    );

    for (final status in HandoffStatus.values.where((s) => s.isPersisted)) {
      final runs = accepted[status]!;
      final outcome = runs ? 'runs and locks readyForDebug' : 'is rejected';
      test('${status.name}: $outcome', () async {
        final io = _io(handoff: withHandoffStatus(_handoffWithScope, status));
        var modelCalls = 0;
        final run = runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          executor: _executorWithAnalysis(onCall: () => modelCalls++),
          confirmFn: (_) => true,
          promptFn: unscriptedPrompt,
          pickFn: (_) => 0,
        );
        if (runs) {
          await run;
          expect(_statusOf(io), HandoffStatus.readyForDebug);
        } else {
          await expectLater(
            run,
            throwsA(isA<InvalidHandoffTransitionException>()),
          );
          expect(modelCalls, 0, reason: 'rejected before any model call');
          expect(_statusOf(io), status);
          expect(_loggedTransitions(io), isEmpty);
        }
      });
    }
  });
}
