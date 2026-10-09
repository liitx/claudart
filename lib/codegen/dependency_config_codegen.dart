// dependency_config_codegen.dart — emit the composed dependency-config const.
//
// Mirrors zedup's user_config_codegen.dart exactly: a pure renderer returns
// the dart source, an injectable writer wraps it in IO so tests stay
// filesystem-free. `claudart link` runs the writer every time it links a
// project, so the generated file never drifts from what the project's own
// pubspec.yaml actually declares.
//
// This is the first consumer of the pattern in claudart — a real gap found
// against zedup's own precedent: claudart had no codegen mechanism at all,
// so cross-repo dependency awareness (e.g. "does this project have dartrix,
// and can it therefore use dartrix's shared types") had nowhere to live
// except ad hoc, per-call-site string checks.
//
// The generated file lives at `lib/generated/dependency_config.g.dart`,
// committed (not gitignored) — same convention as zedup's
// `lib/src/generated/user_config.g.dart`, so a fresh clone's build doesn't
// depend on a codegen step having already run.

import 'dart:io' as io;

/// Header banner emitted at the top of every generated file. Tests assert
/// against this const, never against the literal string.
const String kDependencyConfigGeneratedHeader = '''
// GENERATED — DO NOT EDIT.
// Source: this project's own pubspec.yaml.
// Regenerate by running `claudart link` again.
''';

/// Default filename inside lib/generated/ for the composed const.
const String kDependencyConfigGeneratedFilename = 'dependency_config.g.dart';

/// Relative-to-project-root path `claudart link` writes to.
const String kDependencyConfigGeneratedRelativePath =
    'lib/generated/$kDependencyConfigGeneratedFilename';

/// Injectable writer so tests can substitute an in-memory sink — same seam
/// zedup's `GeneratedFileWriter` typedef provides.
typedef GeneratedFileWriter = Future<void> Function(String path, String content);

Future<void> _defaultGeneratedFileWriter(String path, String content) async {
  final file = io.File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

class DependencyConfigCodegen {
  const DependencyConfigCodegen();

  /// Pure renderer. Returns the dart source for the composed const. No IO,
  /// no defaults — caller passes what was actually detected.
  String render({required bool usesDartrix}) => '''
$kDependencyConfigGeneratedHeader
/// Whether this project's pubspec.yaml declares a dartrix dependency.
/// Gates use of dartrix-provided shared types (e.g. the error-taxonomy
/// top layer) so code referencing them only compiles where dartrix is
/// actually present.
const bool usesDartrix = $usesDartrix;
''';

  /// Writes the rendered source to [projectRoot]/[kDependencyConfigGeneratedRelativePath].
  Future<void> write({
    required bool usesDartrix,
    required String projectRoot,
    GeneratedFileWriter? writer,
  }) async {
    final write_ = writer ?? _defaultGeneratedFileWriter;
    final outputPath = '$projectRoot/$kDependencyConfigGeneratedRelativePath';
    await write_(outputPath, render(usesDartrix: usesDartrix));
  }
}
