// Test files run in one process, so the working directory is shared: a test
// that changes it breaks every other file's relative paths whenever their
// timing overlaps (found when `outside any git repository` did so). Tests give
// code the directory through a seam, they never move the process.

import 'dart:io';

import 'package:test/test.dart';

final _changesCwd = RegExp(r'Directory\.current\s*=[^=]');

List<String> cwdChangers(Map<String, String> sources) => [
      for (final entry in sources.entries)
        if (_changesCwd.hasMatch(entry.value)) entry.key,
    ]..sort();

void main() {
  group('the working directory in tests', () {
    test('an assignment to Directory.current is found', () {
      expect(
        // Two literals, so this file does not match its own rule.
        cwdChangers({'test/a_test.dart': 'Directory.current' ' = temp;'}),
        ['test/a_test.dart'],
      );
    });

    test('reading it is not found, nor comparing it', () {
      expect(
        cwdChangers({
          'a': 'final here = Directory.current;',
          'b': 'expect(Directory.current == other, isTrue);',
        }),
        isEmpty,
      );
    });

    test('no test changes the process working directory', () {
      final sources = {
        for (final file in Directory('test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
      };
      expect(cwdChangers(sources), isEmpty);
    });
  });
}
