import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/commands/flow.dart';
import 'package:claudart/logging/planner_log.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import '../helpers/mocks.dart';

// flow_test.dart — validation-path coverage for runFlow (experimental).
//
// Companion to suggest_test.dart / debug_test.dart. Covers: registration
// validation, the empty-prompt-entered abort, and the reader-produces-
// nothing path. promptFn/pickFn are now injectable — previously hardcoded
// stdin.readLineSync()/arrowMenu() calls.
//
// The checkpoint-resume branch reads a real File from disk (not FileIO), so
// its tests use a temp directory as the workspace. Not covered: the full
// plan-review loop past a successful reader+plan step.

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
    PipelineExecutor(runner: ({required model, required systemPrompt, required message, required workingDir, StepMode mode = StepMode.project}) async => null);

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

  group('runFlow — saved checkpoint', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('claudart_flow_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    MemoryFileIO ioFor(String workspace) {
      final registry = Registry.empty().add(RegistryEntry(
        name: 'my-app',
        projectRoot: _projectRoot,
        workspacePath: workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-01-01',
      ));
      final io = MemoryFileIO();
      registry.save(io: io);
      return io;
    }

    test('approve: checkpoint survives a failed construct step', () async {
      final workspace = tempDir.path;
      final io = ioFor(workspace);

      final checkpointFile = File('$workspace/$flowCheckpointFileName');
      checkpointFile.writeAsStringSync(jsonEncode({
        'createdAt': '2026-01-01T00:00:00',
        'slots': {'plan': 'Do the thing'},
        'bug': 'Something broke',
        'expected': '',
        'projectRoot': _projectRoot,
      }));

      // The construct agent returns nothing, as a dead/unauthenticated
      // `claude` CLI would.
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          executor: _executorWithNoOutput(),
          pickFn: (_) => 0, // "approve saved plan"
        ),
        throwsA(isA<_ExitException>()),
      );

      expect(
        checkpointFile.existsSync(),
        isTrue,
        reason: 'the only copy of the plan must not be deleted before '
            'construct has actually succeeded',
      );
    });

    test('a checkpoint whose top level is not a map is treated as unreadable', () async {
      final workspace = tempDir.path;
      final io = ioFor(workspace);

      // A JSON array: `as Map<String, dynamic>` throws a TypeError, not a
      // FormatException.
      File('$workspace/$flowCheckpointFileName')
          .writeAsStringSync(jsonEncode([1, 2, 3]));

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
  });
}
