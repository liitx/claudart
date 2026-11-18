// A command leaves the process through leaveFor with a named ExitReason, so
// the run's row says why it ended (gap R13). Three files keep their own typed
// endings, recorded as the run's outcome.

import 'dart:io';

import 'package:claudart/io/exit_reason.dart';
import 'package:claudart/io/process_exit.dart';
import 'package:test/test.dart';

/// Files that may call an exit seam directly, and why.
const _ownTypedEndings = <String, String>{
  'lib/io/process_exit.dart': 'defines the one exit',
  'lib/io/exit_reason.dart': 'the one place a reason becomes an exit',
  'lib/commands/debug.dart': 'DebugExitKind, logged as the run outcome',
  'lib/commands/kill.dart': 'KillOutcome, logged as the run outcome',
  'lib/commands/support/project_resolution.dart':
      'ProjectLookupFailure, named just before the exit',
};

/// The exit code each reason must leave with, written out here and not read
/// from the enum, so changing a code on the enum fails a test.
const _expectedExitCode = <ExitReason, int>{
  ExitReason.projectOptionMissingName: 1,
  ExitReason.projectOptionMissingCommand: 1,
  ExitReason.projectOptionUnsupported: 1,
  ExitReason.projectOptionNotFound: 1,
  ExitReason.usageShown: 0,
  ExitReason.versionShown: 0,
  ExitReason.unknownCommand: 1,
  ExitReason.launcherClosed: 0,
  ExitReason.commandFailed: 1,
  ExitReason.rotateBuildFailed: 1,
  ExitReason.compileSucceeded: 0,
  ExitReason.compileFailed: 1,
  ExitReason.hookUsageShown: 1,
  ExitReason.menuInterrupted: 0,
  ExitReason.menuHasNoInput: 1,
  ExitReason.lineEditorInterrupted: 0,
  ExitReason.initDeclined: 0,
  ExitReason.initWorkspaceMissing: 1,
  ExitReason.initKeptExistingFile: 0,
  ExitReason.addNotInGitRepository: 1,
  ExitReason.archivesNone: 0,
  ExitReason.archivesCancelled: 0,
  ExitReason.resumeNoArchives: 0,
  ExitReason.launchOutsideProject: 0,
  ExitReason.chatShellNotInRegisteredProject: 0,
  ExitReason.confirmPendingMissingArguments: 1,
  ExitReason.saveNoHandoff: 0,
  ExitReason.teardownNoHandoff: 0,
  ExitReason.teardownDeferredUntilFixed: 0,
  ExitReason.teardownWorkspaceLocked: 1,
  ExitReason.suggestNoHandoff: 1,
  ExitReason.suggestOverwriteDeclined: 0,
  ExitReason.suggestNoScopeFiles: 1,
  ExitReason.suggestReaderProducedNothing: 1,
  ExitReason.suggestReasonerProducedNothing: 1,
  ExitReason.suggestHandoffNotWritten: 0,
  ExitReason.setupNotInGitRepository: 1,
  ExitReason.setupPathNotFound: 1,
  ExitReason.setupNotLinked: 1,
  ExitReason.setupNeedsTerminal: 1,
  ExitReason.setupCancelled: 0,
  ExitReason.liveHandoffContinued: 0,
  ExitReason.liveHandoffLeftAlone: 0,
  ExitReason.linkUnknownOption: 1,
  ExitReason.linkConflictingSensitivityFlags: 1,
  ExitReason.linkNotInGitRepository: 1,
  ExitReason.linkNoInputForSensitivity: 1,
  ExitReason.flowCheckpointKept: 0,
  ExitReason.flowNoPrompt: 0,
  ExitReason.flowCheckpointSaved: 0,
  ExitReason.flowNotApproved: 0,
  ExitReason.flowProducedNoHandoff: 1,
  ExitReason.rotateNoInputToConfirm: 1,
  ExitReason.preflightUnknownOperation: 1,
  ExitReason.preflightClean: 0,
  ExitReason.preflightWarnings: 0,
  ExitReason.preflightErrors: 1,
  ExitReason.doctorChecksPassed: 0,
  ExitReason.doctorChecksFailed: 1,
  ExitReason.experimentUsageShown: 1,
  ExitReason.experimentCommandFailed: 1,
};

final _exitCall = RegExp(r'\b(exit_|exitFn|exitProcess)\)?\(');

Map<String, String> _sources() => {
      for (final root in ['lib', 'bin'])
        for (final file in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
    };

bool _isComment(String line) => line.trimLeft().startsWith('//');

class _Left implements Exception {
  _Left(this.code);
  final int code;
}

void main() {
  final sources = _sources();

  group('every exit names its reason', () {
    test('no file outside the typed endings calls an exit seam directly', () {
      final offenders = <String>[];
      sources.forEach((path, text) {
        if (_ownTypedEndings.containsKey(path)) return;
        final lines = text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!_isComment(lines[i]) && _exitCall.hasMatch(lines[i])) {
            offenders.add('$path:${i + 1}');
          }
        }
      });
      expect(offenders, isEmpty,
          reason: 'leave through leaveFor(ExitReason.<reason>) instead');
    });

    for (final path in _ownTypedEndings.keys) {
      test('$path still has a reason to call an exit seam', () {
        expect(sources.containsKey(path), isTrue);
        expect(_exitCall.hasMatch(sources[path]!), isTrue);
      });
    }
  });

  group('$ExitReason', () {
    for (final reason in ExitReason.values) {
      test('${reason.name} is used by code outside its definition', () {
        final used = sources.entries.any((entry) =>
            entry.key != 'lib/io/exit_reason.dart' &&
            entry.value.contains('ExitReason.${reason.name}'));
        expect(used, isTrue, reason: 'a reason nothing leaves with is dead');
      });

      test('${reason.name} leaves with ${_expectedExitCode[reason]}', () async {
        await expectLater(
          withExitHook(
            beforeExit: (_, __) {},
            leave: (code) => throw _Left(code),
            body: () async => leaveFor(reason),
          ),
          throwsA(isA<_Left>()
              .having((e) => e.code, 'code', _expectedExitCode[reason])),
        );
      });
    }

    test('every reason has an expected code written out here', () {
      expect(_expectedExitCode.keys.toSet(), ExitReason.values.toSet());
    });

    test('leaving records the reason by name, before the process goes',
        () async {
      final heard = <(int, String?)>[];
      await expectLater(
        withExitHook(
          beforeExit: (code, named) => heard.add((code, named)),
          leave: (code) => throw _Left(code),
          body: () async => leaveFor(ExitReason.usageShown),
        ),
        throwsA(isA<_Left>()),
      );
      expect(heard, [(0, 'usageShown')]);
    });

    test('only a reason that passes a child code takes one', () {
      expect(
        ExitReason.values.where((r) => r.passesChildCode),
        [ExitReason.compileFailed, ExitReason.experimentCommandFailed],
      );
    });

    test('a child code replaces the reason code', () async {
      await expectLater(
        withExitHook(
          beforeExit: (_, __) {},
          leave: (code) => throw _Left(code),
          body: () async =>
              leaveFor(ExitReason.experimentCommandFailed, childCode: 42),
        ),
        throwsA(isA<_Left>().having((e) => e.code, 'code', 42)),
      );
    });
  });
}
