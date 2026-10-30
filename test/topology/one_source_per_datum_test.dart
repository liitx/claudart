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
  homeDirectory(
    pattern: r"\[homeEnvVar\]|\['HOME'\]",
    ownerFile: 'lib/environment.dart',
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

/// Files that look a project up in the registry themselves, each because it
/// differs from the shared lookup (`lookupProject`): it creates the entry,
/// tolerates an unreadable registry, adds a check between the two steps, or
/// lists every project.
const _ownLookupLedger = {
  'lib/commands/doctor.dart',
  'lib/commands/failure_boundary.dart',
  'lib/commands/launch.dart',
  'lib/commands/link.dart',
  'lib/commands/setup.dart',
  'bin/claudart.dart',
};

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

    test('a project is looked up by lookupProject unless the ledger says why',
        () {
      final readers = [
        for (final entry in sources.entries)
          if (!entry.key.endsWith('registry.dart') &&
              !entry.key.endsWith('project_resolution.dart') &&
              entry.value.contains('.findByProjectRoot('))
            entry.key,
      ]..sort();
      expect(readers.toSet().difference(_ownLookupLedger), isEmpty);
    });

    for (final source in DatumSource.values) {
      test('${source.name} is read only through ${source.ownerFile}', () {
        expect(directReaders(source, sources), isEmpty);
      });
    }
  });
}
