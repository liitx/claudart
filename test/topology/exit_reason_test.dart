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

      test('${reason.name} leaves with its code and is recorded by name',
          () async {
        final heard = <(int, String?)>[];
        await expectLater(
          withExitHook(
            beforeExit: (code, named) => heard.add((code, named)),
            leave: (code) => throw _Left(code),
            body: () async => leaveFor(reason),
          ),
          throwsA(isA<_Left>().having((e) => e.code, 'code', reason.exitCode)),
        );
        expect(heard, [(reason.exitCode, reason.name)]);
      });
    }

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
