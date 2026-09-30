import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/suggest.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/tool_grant.dart';
import '../helpers/mocks.dart';

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
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project, ToolGrant toolGrant = ToolGrant.readOnly}) async => null);

void main() {
  group('runSuggest — validation', () {
    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO(); // empty registry
      await expectLater(
        runSuggest(
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
        runSuggest(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
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
}
