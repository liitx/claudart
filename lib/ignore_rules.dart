import 'file_io.dart';

/// Default glob-style patterns applied when .claudartignore is missing.
const _defaultPatterns = [
  '**/*.g.dart',
  '**/*.freezed.dart',
  '**/*.mocks.dart',
  'build/',
  '.dart_tool/',
];

/// Determines which files should be excluded from scanning.
class IgnoreRules {
  final List<String> _patterns;

  const IgnoreRules(this._patterns);

  /// Returns true if [relativePath] matches any ignore pattern.
  bool shouldIgnore(String relativePath) {
    for (final pattern in _patterns) {
      if (_matches(relativePath, pattern)) return true;
    }
    return false;
  }

  bool _matches(String path, String pattern) {
    // Directory prefix pattern (ends with /)
    if (pattern.endsWith('/')) {
      final dir = pattern.substring(0, pattern.length - 1);
      return path.startsWith('$dir/') || path == dir;
    }
    // Glob with ** wildcard (e.g. **/*.g.dart)
    if (pattern.startsWith('**/')) {
      final suffix = pattern.substring(3); // e.g. '*.g.dart'
      if (suffix.startsWith('*.')) {
        return path.endsWith(suffix.substring(1)); // match '.g.dart'
      }
      return path.endsWith(suffix) || path.contains('/$suffix');
    }
    // Simple wildcard suffix (*.ext)
    if (pattern.startsWith('*.')) {
      return path.endsWith(pattern.substring(1));
    }
    // Exact match or path suffix
    return path == pattern || path.endsWith('/$pattern');
  }
}

/// Loads ignore rules from [projectRoot]/.claudartignore.
/// Falls back to [_defaultPatterns] if the file does not exist.
IgnoreRules loadIgnoreRules(String projectRoot, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final ignorePath = '$projectRoot/.claudartignore';
  final content = fileIO.read(ignorePath);
  if (content.isEmpty) return const IgnoreRules(_defaultPatterns);

  final lines = content
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  return IgnoreRules(lines.isEmpty ? _defaultPatterns : lines);
}
