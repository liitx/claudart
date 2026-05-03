import 'token_map.dart';
import 'detector.dart';

/// Replaces sensitive tokens in text with their mapped abstract tokens,
/// and provides the inverse operation.
class Abstractor {
  /// Replaces all sensitive tokens in [text] with their mapped counterparts.
  /// New tokens are assigned in [map] for any unmapped sensitive identifiers.
  String abstract(String text, TokenMap map, SensitivityDetector detector) {
    final sensitive = detector.detectInText(text);
    if (sensitive.isEmpty) return text;

    // Sort longest first to avoid partial replacement conflicts.
    sensitive.sort((a, b) => b.length.compareTo(a.length));

    var result = text;
    for (final token in sensitive) {
      final typePrefix = _inferType(token, map);
      final mapped = map.tokenFor(token, typePrefix);
      // Use word boundaries to avoid corrupting related tokens
      result = result.replaceAll(RegExp(r'\b' + RegExp.escape(token) + r'\b'), mapped);
    }
    return result;
  }

  /// Restores abstracted tokens to real names using the [map].
  String deabstract(String text, TokenMap map) {
    // Build reverse: mapped token -> real name
    // Collect all tokens by scanning the text for token-shaped strings.
    final tokenPattern = RegExp(r'\b[A-Za-z]+:[A-Z]{1,2}\b');
    var result = text;
    final seen = <String>{};
    for (final m in tokenPattern.allMatches(text)) {
      final tok = m.group(0)!;
      if (seen.contains(tok)) continue;
      seen.add(tok);
      // Verify the token exists in the map before replacing
      if (map.contains(tok) || map.realFor(tok) != null) {
        final real = map.realFor(tok);
        if (real != null) result = result.replaceAll(RegExp(r'\b' + RegExp.escape(tok) + r'\b'), real);
      }
    }
    return result;
  }

  /// Returns true when [text] contains no sensitive tokens.
  bool isNotSensitive(String text, SensitivityDetector detector) {
    return detector.detectInText(text).isEmpty;
  }

  String _inferType(String name, TokenMap map) {
    // If already in map, return its existing prefix
    if (map.contains(name)) {
      final token = map.tokenFor(name, 'Class');
      final colon = token.indexOf(':');
      if (colon >= 0) return token.substring(0, colon);
    }
    if (name.endsWith('Bloc')) return 'Bloc';
    if (name.endsWith('Cubit')) return 'Cubit';
    if (name.endsWith('State')) return 'BlocState';
    if (name.endsWith('Event')) return 'BlocEvent';
    if (name.endsWith('Repository')) return 'Repository';
    if (name.endsWith('Widget')) return 'Widget';
    if (name.endsWith('Provider')) return 'Provider';
    if (name.endsWith('Model')) return 'Model';
    if (name.endsWith('Enum') || _isEnum(name)) return 'Enum';
    if (name.endsWith('X') && name.length > 2) return 'Extension';
    return 'Class';
  }

  bool _isEnum(String name) => false; // enum detection is handled at scan time
}

/// Shared singleton instance.
final abstractor = Abstractor();
