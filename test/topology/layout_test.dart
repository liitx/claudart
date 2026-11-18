// Layout (invariant I5): a file's folder says what it is. The root of `lib/`
// holds only the public surface; `lib/commands/` holds only commands.

import 'dart:io';

import 'package:test/test.dart';

/// The files at the root of `lib/`: the barrel consumers import, and the two
/// files zedup imports by path (changing their path would break it).
const _libRootFiles = {'claudart.dart', 'registry.dart', 'version.dart'};

/// A top-level function a command exposes: `Future<...> runName(` or
/// `void runName(` at the start of a line.
final _commandEntry = RegExp(
  r'^(?:Future<[^>]*>|void|\w+)\s+run[A-Z]\w*\(',
  multiLine: true,
);

List<String> _dartFilesIn(String directory) => [
      for (final entity in Directory(directory).listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.split('/').last,
    ]..sort();

void main() {
  group('layout', () {
    test('the root of lib holds only the public surface', () {
      expect(_dartFilesIn('lib').toSet().difference(_libRootFiles), isEmpty);
    });

    test('lib/commands holds only files that define a command to run', () {
      final notCommands = [
        for (final name in _dartFilesIn('lib/commands'))
          if (!_commandEntry
              .hasMatch(File('lib/commands/$name').readAsStringSync()))
            name,
      ];
      expect(notCommands, isEmpty);
    });

    test('a non-command file in lib/commands is found', () {
      expect(_commandEntry.hasMatch('const seams = 1;'), isFalse);
      expect(
        _commandEntry.hasMatch('Future<void> runKill({\n  int x,\n}) async {'),
        isTrue,
      );
    });
  });
}
