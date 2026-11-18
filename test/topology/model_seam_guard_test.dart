// model_seam_guard_test.dart — a test never reaches the real model.
//
// A command that runs a pipeline builds its own executor when none is passed,
// and that executor starts the real `claude` process. On a machine where the CLI
// is installed and signed in, a test that forgets to pass one would spend model
// calls, so every test call of such a command must pass its own `executor`.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Commands that run a pipeline when no executor is given, and the argument that
/// replaces the real one.
const _commands = <String, String>{
  'runTeardown': 'executor',
};

/// Every Dart file under test/, with its text.
Map<String, String> _testSources() => {
      for (final entity in Directory('test').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          p.normalize(entity.path): entity.readAsStringSync(),
    };

/// The `line` of each call of [command] in [source] whose argument list does not
/// name [argument].
List<int> callsMissingArgument(String source, String command, String argument) {
  final missing = <int>[];
  var from = 0;
  while (true) {
    final start = source.indexOf('$command(', from);
    if (start < 0) break;
    from = start + command.length;
    // The definition and any use as a tear-off are not calls.
    final before = start == 0 ? '' : source[start - 1];
    if (RegExp(r'[\w.]').hasMatch(before)) continue;
    var depth = 0;
    var end = start + command.length;
    for (; end < source.length; end++) {
      if (source[end] == '(') depth++;
      if (source[end] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    final arguments = source.substring(start, end);
    if (!arguments.contains('$argument:')) {
      missing.add('\n'.allMatches(source.substring(0, start)).length + 1);
    }
  }
  return missing;
}

void main() {
  group('callsMissingArgument', () {
    test('finds a call that does not name the argument', () {
      expect(
        callsMissingArgument('a\nrunIt(io: x);', 'runIt', 'executor'),
        [2],
      );
    });

    test('passes a call that names it, even across lines', () {
      expect(
        callsMissingArgument('runIt(\n  io: x,\n  executor: e,\n);', 'runIt', 'executor'),
        isEmpty,
      );
    });

    test('ignores a longer name that ends in the command', () {
      expect(callsMissingArgument('myrunIt(io: x);', 'runIt', 'executor'), isEmpty);
    });

    test('a nested call is not mistaken for the end of the arguments', () {
      expect(
        callsMissingArgument(
          'runIt(io: f(1), executor: e);',
          'runIt',
          'executor',
        ),
        isEmpty,
      );
    });
  });

  group('every test call passes its own executor', () {
    final sources = _testSources();
    _commands.forEach((command, argument) {
      test(command, () {
        final offenders = [
          for (final entry in sources.entries)
            for (final line in callsMissingArgument(entry.value, command, argument))
              '${entry.key}:$line',
        ];
        expect(
          offenders,
          isEmpty,
          reason: '$command is called without `$argument:`, so it would start '
              'the real model: pass a fake executor',
        );
      });
    });
  });
}
