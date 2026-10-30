// One source per datum (invariant I3): the process environment, spawned
// processes and the git executable are each reached from exactly one file;
// every other file asks that one.

import 'dart:io';

import 'package:test/test.dart';

/// A datum claudart reads from outside itself, the way it is spelled when
/// reached directly, and the single file allowed to spell it.
enum DatumSource {
  environment(
    pattern: r'\bPlatform\.environment\b',
    ownerFile: 'lib/environment.dart',
  ),
  process(
    pattern: r'\bProcess\.(run|runSync|start)\(',
    ownerFile: 'lib/process_runner.dart',
  ),
  gitExecutable(
    pattern: r"'git'",
    ownerFile: 'lib/git_utils.dart',
  );

  const DatumSource({required this.pattern, required this.ownerFile});

  /// How a direct read looks in source.
  final String pattern;

  /// The only file that may contain [pattern].
  final String ownerFile;
}

/// Files outside [source]'s owner that read the datum directly, comment lines
/// excluded.
List<String> directReaders(DatumSource source, Map<String, String> sources) {
  final direct = RegExp(source.pattern);
  return [
    for (final entry in sources.entries)
      if (entry.key != source.ownerFile)
        if (entry.value
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .any(direct.hasMatch))
          entry.key,
  ]..sort();
}

Map<String, String> _readSources() => {
      for (final root in ['lib', 'bin'])
        for (final file in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
    };

void main() {
  group('$DatumSource', () {
    test('a second file reading the datum directly is found', () {
      expect(
        directReaders(DatumSource.environment, {
          DatumSource.environment.ownerFile: 'Platform.environment',
          'lib/other.dart': 'final e = Platform.environment;',
        }),
        ['lib/other.dart'],
      );
    });

    test('a comment mentioning the datum is not a read', () {
      expect(
        directReaders(DatumSource.environment, {
          'lib/other.dart': '// Platform.environment is read in one place',
        }),
        isEmpty,
      );
    });

    final sources = _readSources();
    for (final source in DatumSource.values) {
      test('${source.name} is read only through ${source.ownerFile}', () {
        expect(directReaders(source, sources), isEmpty);
      });
    }
  });
}
