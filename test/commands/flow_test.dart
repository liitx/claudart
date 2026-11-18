import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:claudart/commands/flow.dart';
import 'package:claudart/commands/support/live_handoff.dart';
import 'package:claudart/logging/planner_log.dart';
import 'package:claudart/config/paths.dart';
import 'package:claudart/workspace/workspace_config.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/templates/handoff_template.dart' show blankHandoff;
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/session/md_io.dart' show withHandoffStatus;
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/route_tag.dart';
import '../helpers/mocks.dart';
import '../helpers/logged_moves.dart';
import '../helpers/unscripted.dart';
import '../helpers/project_fixture.dart';

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

const _projectRoot = ProjectFixture.root;
const _workspace   = ProjectFixture.workspace;

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


/// An executor whose every step answers with [text].
PipelineExecutor _executorAnswering(String text) => PipelineExecutor(
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

/// An executor that counts the model calls it is asked for.
PipelineExecutor _countingExecutor(void Function() onCall) => PipelineExecutor(
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
        onCall();
        return StepResult(
          text:
              '<${RouteTag.handoff.wireTag}>$_constructedHandoff</${RouteTag.handoff.wireTag}>',
          usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
        );
      },
    );

const _constructedHandoff = '''## Status
ready-for-suggest

---

## Bug
The parser drops a line.

---

## Root Cause
The splitter stops early.

---

## Scope
### Files in play
- lib/parser.dart''';

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

  group('runFlow — unreadable workspace.json', () {
    test('stops with a typed failure, before asking for a prompt', () async {
      final io = _io();
      io.write(workspaceConfigPathFor(_workspace), '{not valid json');
      await expectLater(
        runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          promptFn: (question, {optional = false}) => fail('was prompted'),
        ),
        throwsA(isA<WorkspaceConfigUnreadableException>()),
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

  // `flow` is another way into a session (it replaces `setup`), so it enters the
  // state machine through an event of its own and writes through the one
  // writer: the move is on record, and a handoff it replaces is visible.
  group('runFlow — the handoff it writes', () {
    MemoryFileIO ioWith({String? existingHandoff}) {
      const workspace = _workspace;
      final io = MemoryFileIO();
      Registry.empty()
          .add(const RegistryEntry(
            name: 'my-app',
            projectRoot: _projectRoot,
            workspacePath: workspace,
            createdAt: '2026-01-01',
            lastSession: '2026-01-01',
          ))
          .save(io: io);
      if (existingHandoff != null) {
        io.write(handoffPathFor(workspace), existingHandoff);
      }
      io.write(
        '$workspace/$flowCheckpointFileName',
        jsonEncode({
          'createdAt': '2026-01-01T00:00:00',
          'slots': {'plan': 'Do the thing'},
          'bug': 'The parser drops a line.',
          'expected': '',
          'projectRoot': _projectRoot,
        }),
      );
      return io;
    }

    Future<void> runWith(MemoryFileIO io) => runZoned(
          () => runFlow(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            plannerLog: _silentPlannerLog(),
            executor: _executorAnswering(
                '<${RouteTag.handoff.wireTag}>$_constructedHandoff</${RouteTag.handoff.wireTag}>'),
            pickFn: (_) => 0, // approve the saved plan
          ),
          zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
        );

    test('a session started by flow records the entry move, noHandoff to '
        'readyForSuggest', () async {
      final io = ioWith();
      await runWith(io);
      expect(io.read(handoffPathFor(_workspace)),
          contains('The splitter stops early.'));
      expect(loggedMoves(io, _workspace), [
        {
          'command': 'flow',
          'from': HandoffStatus.noHandoff.name,
          'event': HandoffEvent.flowConstructed.name,
          'to': HandoffStatus.readyForSuggest.name,
        },
      ]);
    });

    // What `setup` does over a live handoff (measured with the real binary):
    // it asks, "Start fresh" archives the old handoff first, and the move is
    // logged as one the table lacks.
    final liveHandoff = withHandoffStatus(
      blankHandoff.replaceFirst('_Not yet determined._', 'an older bug'),
      HandoffStatus.debugInProgress,
    );

    int Function(List<String>) choosing(LiveHandoffMenu choice) => (items) =>
        items.any((item) => item.contains('Start fresh'))
            ? choice.index
            : 0; // approve the saved plan

    Future<({int modelCalls})> runOver(
      MemoryFileIO io,
      LiveHandoffMenu choice,
    ) async {
      var modelCalls = 0;
      try {
        await runZoned(
          () => runFlow(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            plannerLog: _silentPlannerLog(),
            executor: _countingExecutor(() => modelCalls++),
            pickFn: choosing(choice),
          ),
          zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
        );
      } on _ExitException {
        // Continue and Back leave through exit 0.
      }
      return (modelCalls: modelCalls);
    }

    int archived(MemoryFileIO io) => io.files.keys
        .where((path) => path.startsWith(archiveDirFor(_workspace)))
        .length;

    test('over a live handoff "Start fresh" archives the old one first, then '
        'writes, and the move is logged as rejected', () async {
      final io = ioWith(existingHandoff: liveHandoff);
      await runOver(io, LiveHandoffMenu.startFresh);
      expect(archived(io), greaterThan(0));
      expect(
        io.files.entries
            .where((e) => e.key.startsWith(archiveDirFor(_workspace)))
            .any((e) => e.value.contains('an older bug')),
        isTrue,
        reason: 'the replaced handoff is kept in the archive',
      );
      expect(io.read(handoffPathFor(_workspace)),
          contains('The splitter stops early.'));
      expect(loggedMoves(io, _workspace), [
        {
          'command': 'flow',
          'from': HandoffStatus.debugInProgress.name,
          'event': HandoffEvent.flowConstructed.name,
          'rejected': true,
        },
      ]);
    });

    test('over a live handoff "Continue" keeps it, spends no model call and '
        'archives nothing', () async {
      final io = ioWith(existingHandoff: liveHandoff);
      final result = await runOver(io, LiveHandoffMenu.resume);
      expect(io.read(handoffPathFor(_workspace)), liveHandoff);
      expect(result.modelCalls, 0);
      expect(archived(io), 0);
      expect(loggedMoves(io, _workspace), isEmpty);
    });

    test('over a live handoff "Back" cancels the same way', () async {
      final io = ioWith(existingHandoff: liveHandoff);
      final result = await runOver(io, LiveHandoffMenu.back);
      expect(io.read(handoffPathFor(_workspace)), liveHandoff);
      expect(result.modelCalls, 0);
      expect(archived(io), 0);
    });

    test('with no live handoff it does not ask and archives nothing', () async {
      final io = ioWith();
      var asked = false;
      await runZoned(
        () => runFlow(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
          plannerLog: _silentPlannerLog(),
          executor: _executorAnswering(
              '<${RouteTag.handoff.wireTag}>$_constructedHandoff</${RouteTag.handoff.wireTag}>'),
          pickFn: (items) {
            asked = asked || items.any((item) => item.contains('Start fresh'));
            return 0;
          },
        ),
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
      );
      expect(asked, isFalse);
      expect(archived(io), 0);
    });
  });

  group('runFlow — saved checkpoint', () {
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
      const workspace = _workspace;
      final io = ioFor(workspace);

      const checkpointPath = '$workspace/$flowCheckpointFileName';
      io.write(checkpointPath, jsonEncode({
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
        io.fileExists(checkpointPath),
        isTrue,
        reason: 'the only copy of the plan must not be deleted before '
            'construct has actually succeeded',
      );
    });

    test('a checkpoint whose top level is not a map is treated as unreadable', () async {
      const workspace = _workspace;
      final io = ioFor(workspace);

      // A JSON array: `as Map<String, dynamic>` throws a TypeError, not a
      // FormatException.
      io.write('$workspace/$flowCheckpointFileName', jsonEncode([1, 2, 3]));

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
