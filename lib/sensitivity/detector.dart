import '../assets/corpus.dart';

/// Threshold above which a token is considered potentially sensitive.
const double _sensitiveThreshold = 0.5;

/// Regex: PascalCase identifiers (e.g., SearchBloc, DataRepository)
final _pascalCase = RegExp(r'\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\b');

/// Regex: camelCase compound words with at least two parts
final _camelCase = RegExp(r'\b[a-z]+(?:[A-Z][a-z]+)+\b');

/// Regex: snake_case .dart filename stems (without extension)
final _snakeDart = RegExp(r'\b[a-z][a-z0-9]*(?:_[a-z][a-z0-9]+)+\b');

/// Safe passthrough identifiers that are never considered sensitive.
const _safeList = {
  'String', 'int', 'double', 'bool', 'num', 'List', 'Map', 'Set',
  'Future', 'Stream', 'void', 'dynamic', 'Object', 'BuildContext',
  'Widget', 'Key', 'GlobalKey', 'State', 'StatelessWidget',
  'StatefulWidget', 'TextStyle', 'Color', 'Size', 'Offset', 'EdgeInsets',
  'Padding', 'Scaffold', 'Column', 'Row', 'Text', 'Container', 'Expanded',
  'SizedBox', 'Navigator', 'Route', 'MaterialApp', 'ThemeData',
  'Bloc', 'Cubit', 'BlocBuilder', 'BlocProvider', 'BlocListener',
  'Emitter', 'StreamSubscription', 'DateTime', 'Duration', 'Timer',
  'Completer', 'Uint8List', 'ByteData', 'jsonDecode', 'jsonEncode',
  'Exception', 'Error', 'StackTrace', 'print', 'debugPrint',
  'Provider', 'ConsumerWidget', 'WidgetRef', 'Ref',
};

/// Detects sensitive tokens using TF-IDF corpus + regex heuristics.
class SensitivityDetector {
  final Map<String, double> _corpus;

  const SensitivityDetector(this._corpus);

  /// Returns true if [token] is likely sensitive (project-specific).
  bool isSensitive(String token) {
    if (_safeList.contains(token)) return false;
    if (_corpus.containsKey(token)) {
      return (_corpus[token]! >= _sensitiveThreshold);
    }
    // Not in corpus → high IDF → sensitive
    return true;
  }

  /// Extracts all sensitive identifiers from [text].
  List<String> detectInText(String text) {
    final found = <String>{};
    for (final m in _pascalCase.allMatches(text)) {
      final tok = m.group(0)!;
      if (isSensitive(tok)) found.add(tok);
    }
    for (final m in _camelCase.allMatches(text)) {
      final tok = m.group(0)!;
      if (isSensitive(tok)) found.add(tok);
    }
    for (final m in _snakeDart.allMatches(text)) {
      final tok = m.group(0)!;
      if (isSensitive(tok)) found.add(tok);
    }
    return found.toList();
  }
}

/// Default detector using the bundled corpus.
const defaultDetector = SensitivityDetector(dartCorpus);
