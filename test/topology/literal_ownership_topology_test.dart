// literal_ownership_topology_test.dart — facts that have one owner are spelled
// in one place, and nowhere else in the code or the tests.
//
// Three kinds of fact are proven here:
//   - a log file's name is spelled only by LogFile (and by its own spec test,
//     which pins the names as a contract),
//   - the fixture project's paths are spelled only by ProjectFixture,
//   - a test title names a production type with the type itself ($Type), never
//     by writing the name as text, so renaming the type breaks the title.
//
// The scan reads the sources, so a new copy fails here at once, naming the file
// and line, instead of drifting until someone notices.

import 'dart:io';

import 'package:claudart/logging/log_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/project_fixture.dart';

const _sourceRoots = ['lib', 'bin', 'test'];
const _logFileOwners = {
  'lib/logging/log_file.dart',
  'test/logging/log_file_test.dart',
};
const _fixturePathOwner = 'test/helpers/project_fixture.dart';

/// How many test titles still write a production type's name as text. A ratchet:
/// it may only go down. Converting a title to `$Type` lowers it; adding one
/// fails the test below.
const _knownTitlesNamingATypeAsText = 184;

/// Every Dart file under the source roots, with its lines.
Map<String, List<String>> _sources() => {
      for (final root in _sourceRoots)
        if (Directory(root).existsSync())
          for (final entity in Directory(root).listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart'))
              p.normalize(entity.path): entity.readAsLinesSync(),
    };

/// The files that spell [literal] as a quoted string, with their line numbers.
Map<String, List<int>> _spelling(
  Map<String, List<String>> sources,
  String literal,
) {
  final quotes = ["'$literal'", '"$literal"'];
  return {
    for (final entry in sources.entries)
      if (entry.value.any((line) => quotes.any(line.contains)))
        entry.key: [
          for (var i = 0; i < entry.value.length; i++)
            if (quotes.any(entry.value[i].contains)) i + 1,
        ],
  };
}

/// The names of the types the production code declares.
Set<String> _declaredTypes(Map<String, List<String>> sources) {
  final declaration = RegExp(
    r'^(?:abstract |final |sealed |base |interface |mixin )*'
    r'(?:class|enum|typedef)\s+(\w+)',
  );
  return {
    for (final entry in sources.entries)
      if (entry.key.startsWith('lib/'))
        for (final line in entry.value)
          if (declaration.firstMatch(line) != null)
            declaration.firstMatch(line)!.group(1)!,
  };
}

void main() {
  final sources = _sources();

  group('a log file name has one owner', () {
    for (final file in LogFile.values) {
      test(file.name, () {
        expect(
          _spelling(sources, file.fileName).keys.toSet().difference(
                _logFileOwners,
              ),
          isEmpty,
          reason: '${file.fileName} is spelled outside its owners: reach the '
              'log through LogFile instead',
        );
      });
    }
  });

  group('a fixture path has one owner', () {
    const paths = {
      'root': ProjectFixture.root,
      'workspace': ProjectFixture.workspace,
    };
    paths.forEach((name, path) {
      test(name, () {
        expect(
          _spelling(sources, path).keys.toSet().difference({_fixturePathOwner}),
          isEmpty,
          reason: 'the fixture $name path is spelled outside '
              '$_fixturePathOwner: use ProjectFixture instead',
        );
      });
    });
  });

  group('a test title names a type by the type, not by text', () {
    test('no new title writes a type name as text', () {
      final types = _declaredTypes(sources);
      final title = RegExp(r"^\s*(?:group|test)\('(\w+)[^'$]*'");
      final offenders = <String>[
        for (final entry in sources.entries)
          if (entry.key.startsWith('test/'))
            for (var i = 0; i < entry.value.length; i++)
              if (title.firstMatch(entry.value[i]) != null &&
                  types.contains(title.firstMatch(entry.value[i])!.group(1)))
                '${entry.key}:${i + 1}',
      ];
      expect(
        offenders.length,
        lessThanOrEqualTo(_knownTitlesNamingATypeAsText),
        reason: 'a title writes a production type as text; write \$Type '
            'instead. Newest offenders: ${offenders.take(5).join(', ')}',
      );
    });
  });
}
