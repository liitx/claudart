// sensitive_logs_test.dart — a sensitive project's logs never hold its names.
//
// Runs real commands against a project marked sensitive, with a model runner
// that fails with a message naming the project's own identifiers, then reads
// every file under the project's logs directory. The same run on a project that
// is not sensitive must contain the names: that proves the check can see them,
// so an empty result for the sensitive project means something.

import 'dart:async';

import 'package:claudart/commands/debug.dart';
import 'package:claudart/commands/suggest.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/registry.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';
import '../helpers/project_fixture.dart';
import '../helpers/unscripted.dart';

const _secret = 'VolumeBloc';
const _failure = '$_secret exploded in VolumeRepository.load';

const _handoff = '''# Agent Handoff — my-app

## Status

ready-for-debug

## Bug

$_secret crashes on load.

## Root Cause

Found it.

## Scope

### Files in play
- `lib/volume_bloc.dart`
''';

Never _noExit(int code) => throw StateError('exit($code)');

MemoryFileIO _sandbox({required bool sensitive, required String status}) {
  final io = MemoryFileIO(
    files: {
      handoffPathFor(ProjectFixture.workspace):
          _handoff.replaceFirst('ready-for-debug', status),
    },
  );
  Registry.empty()
      .add(
        RegistryEntry(
          name: 'my-app',
          projectRoot: ProjectFixture.root,
          workspacePath: ProjectFixture.workspace,
          createdAt: '2026-01-01',
          lastSession: '2026-03-15',
          sensitivityMode: sensitive,
        ),
      )
      .save(io: io);
  return io;
}

/// A model runner that fails with a message naming the project's identifiers.
PipelineExecutor _failingExecutor() => PipelineExecutor(
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
          throw Exception(_failure),
    );

/// Everything written under the project's logs directory, as one text.
String _logsOf(MemoryFileIO io) {
  final logs = logsDirFor(ProjectFixture.workspace);
  return [
    for (final entry in io.files.entries)
      if (entry.key.startsWith(logs)) entry.value,
  ].join('\n');
}

/// A command's run that fails at its first model step, and the status its
/// handoff must be in for the run to reach one.
typedef _FailingRun = ({
  String status,
  Future<void> Function(MemoryFileIO io) run,
});

final _failingRuns = <String, _FailingRun>{
  'suggest': (status: 'suggest-investigating', run: (io) => runSuggest(
        io: io,
        projectRootOverride: ProjectFixture.root,
        exitFn: _noExit,
        executor: _failingExecutor(),
        confirmFn: unscriptedConfirm,
        promptFn: unscriptedPrompt,
        pickFn: unscriptedPick,
      )),
  'debug': (status: 'ready-for-debug', run: (io) => runDebug(
        io: io,
        projectRootOverride: ProjectFixture.root,
        exitFn: _noExit,
        executor: _failingExecutor(),
        pickFn: unscriptedPick,
      )),
};

void main() {
  _failingRuns.forEach((command, failing) {
    group('$command failing at a model step', () {
      Future<String> logsAfterFailure({required bool sensitive}) async {
        final io = _sandbox(sensitive: sensitive, status: failing.status);
        await runZoned(
          () async {
            try {
              await failing.run(io);
            } on Object {
              // The failure is the point of the run; only the logs matter.
            }
          },
          zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
        );
        return _logsOf(io);
      }

      test('a project that is not sensitive logs the names', () async {
        expect(await logsAfterFailure(sensitive: false), contains(_secret));
      });

      test('a sensitive project logs none of them', () async {
        expect(
          await logsAfterFailure(sensitive: true),
          isNot(contains(_secret)),
        );
      });
    });
  });
}
