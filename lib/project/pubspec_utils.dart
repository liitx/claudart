import 'package:path/path.dart' as p;
import '../io/file_io.dart';

/// Reads Dart SDK and Flutter version constraints from a project's pubspec.yaml.
({String? sdk, String? flutter}) readProjectEnv(
  String projectDir, {
  FileIO? io,
}) {
  final fileIO = io ?? const RealFileIO();
  final pubspecPath = p.join(projectDir, 'pubspec.yaml');

  if (!fileIO.fileExists(pubspecPath)) return (sdk: null, flutter: null);

  final content = fileIO.read(pubspecPath);

  final envBlock = RegExp(
    r'^environment\s*:\s*\n((?:[ \t]+\S[^\n]*\n?)+)',
    multiLine: true,
  ).firstMatch(content)?.group(1) ?? '';

  String? extract(String key) {
    final m = RegExp(
      r'''^\s*''' + key + r'''\s*:\s*['"]?([^'"\n]+?)['"]?\s*$''',
      multiLine: true,
    ).firstMatch(envBlock);
    return m?.group(1)?.trim();
  }

  return (sdk: extract('sdk'), flutter: extract('flutter'));
}
