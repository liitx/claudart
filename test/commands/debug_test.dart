import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/debug.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/tool_grant.dart';
import '../helpers/mocks.dart';

// debug_test.dart — validation-path coverage for runDebug.
//
// Companion to suggest_test.dart. Covers: registration/handoff/scope
// validation exits, the status-confirmation gate (now injectable via
// confirmFn — previously hardcoded stdin.readLineSync()), and the
// reader-step-produces-nothing path via an injected PipelineExecutor,
// plus the resolveEditPath sandbox guard.
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
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project, ToolGrant toolGrant = ToolGrant.readOnly}) async => null);

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

  // A model-supplied <EDIT_FILE path="..."> must resolve inside projectRoot.
  // Absolute paths and `..` escapes are refused, never joined blindly.
  group('resolveEditPath', () {
    const root = '/home/user/project';

    test('plain relative path resolves inside projectRoot', () {
      final resolved = resolveEditPath(root, 'lib/example.dart');
      expect(resolved, equals('/home/user/project/lib/example.dart'));
    });

    test('parent-escape is refused', () {
      expect(resolveEditPath(root, '../x'), isNull);
    });

    test('absolute path is refused', () {
      expect(resolveEditPath(root, '/home/user/.ssh/authorized_keys'), isNull);
    });

    test('escape then re-descend is still refused', () {
      expect(resolveEditPath(root, 'a/../../x'), isNull);
    });

    test('internal .. that stays inside projectRoot resolves', () {
      final resolved = resolveEditPath(root, 'a/../b.dart');
      expect(resolved, equals('/home/user/project/b.dart'));
    });
  });
}
