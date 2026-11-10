// mirror.dart — which test file mirrors a source file
//
// The testing convention of both repositories: `lib/foo/bar.dart` is tested by
// `test/foo/bar_test.dart`, and dartrix's own tests drop the `src/` its sources
// sit under. A source file with no such test is a triage gap by itself, so the
// answer can be null.

import 'dart:io';

/// The mirrored test of [libFile] (relative to [root]), or null when there is
/// none.
String? mirroredTest(String root, String libFile) {
  final relative = libFile.replaceFirst(RegExp(r'^lib/'), '');
  final candidates = {
    'test/${relative.replaceFirst(RegExp(r'\.dart$'), '_test.dart')}',
    'test/${relative.replaceFirst(RegExp(r'^src/'), '').replaceFirst(RegExp(r'\.dart$'), '_test.dart')}',
  };
  for (final candidate in candidates) {
    if (File('$root/$candidate').existsSync()) return candidate;
  }
  return null;
}

/// The `.dart` files under [directory] of [root], relative to [root], sorted.
List<String> sourceFilesUnder(String root, String directory) {
  final base = Directory('$root/$directory');
  final files = base.existsSync()
      ? [
          for (final entity in base.listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart'))
              entity.path.substring(root.length + 1),
        ]
      : [if (File('$root/$directory').existsSync()) directory];
  return files..sort();
}
