import 'dart:async';
import 'package:test/test.dart';
import 'package:claudart/commands/flow.dart';
import 'package:claudart/logging/planner_log.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/tool_grant.dart';
import '../helpers/mocks.dart';

// flow_test.dart — validation-path coverage for runFlow (experimental).
//
// Companion to suggest_test.dart / debug_test.dart. Covers: registration
// validation, the empty-prompt-entered abort, and the reader-produces-
// nothing path. promptFn/pickFn are now injectable — previously hardcoded
// stdin.readLineSync()/arrowMenu() calls.
//
// Not covered: the checkpoint-resume branch (reads a real File from disk
// via File(checkpointPath).existsSync(), not FileIO — a separate,
// pre-existing gap, not introduced by this pass) and the full plan-review
// loop past a successful reader+plan step.

const _projectRoot = '/projects/my-app';
const _workspace   = '/workspaces/my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

MemoryFileIO _io() {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final registry = Registry.empty().add(entry);
  final io = MemoryFileIO();
  registry.save(io: io);
  return io;
}

PlannerLog _silentPlannerLog() => PlannerLog(path: '/tmp/ignored', appender: (_, __) {});

PipelineExecutor _executorWithNoOutput() =>
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project, ToolGrant toolGrant = ToolGrant.readOnly}) async => null);

void main() {
  group('runFlow — validation', () {
    test('exits 1 when project is not registered', () async {
      final io = MemoryFileIO();
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('runFlow — empty prompt', () {
    test('exits 0 when no prompt is entered', () async {
      final io = _io();
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          promptFn: (question, {optional = false}) => null,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(0))),
      );
    });

    test('empty string (not just null) also aborts', () async {
      final io = _io();
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          promptFn: (question, {optional = false}) => '   ',
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', equals(0))),
      );
    });
  });

  group('runFlow — reader step produces nothing', () {
    test('exits 1 without reaching the plan-review loop', () async {
      final io = _io();
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          promptFn: (question, {optional = false}) => 'fix the flaky test',
          executor: _executorWithNoOutput(),
        ),
        throwsA(isA<_ExitException>()),
      );
    });
  });

  group('runFlow — project resolution', () {
    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      try {
        await runZoned(
          () => runFlow(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            plannerLog: _silentPlannerLog(),
            promptFn: (question, {optional = false}) => null,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        );
      } on _ExitException {
        // expected — empty prompt aborts, print already happened before that
      }
      expect(output.join('\n'), contains('Project  : my-app'));
    });
  });
}
