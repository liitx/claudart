import 'dart:convert';
import '../file_io.dart';

/// A relational, append-only token map that assigns stable short tokens
/// to real identifier names.
///
/// Token format: `TypePrefix:Letter` (e.g., `Bloc:A`, `Repository:B`).
/// Once assigned, tokens are never reassigned.
class TokenMap {
  final Map<String, dynamic> _byToken = {};
  // Maps realName -> token for fast forward lookup
  final Map<String, String> _byReal = {};

  /// Counter per type prefix, keyed by prefix string.
  final Map<String, int> _counters = {};

  /// Number of entries (non-deprecated).
  int get size => _byToken.length;

  /// Returns the token for [realName] under [typePrefix].
  /// Assigns a new sequential token if not yet mapped.
  /// Deprecated tokens are never reassigned.
  String tokenFor(String realName, String typePrefix) {
    if (_byReal.containsKey(realName)) return _byReal[realName]!;
    final token = _nextToken(typePrefix);
    _byToken[token] = <String, dynamic>{'r': realName};
    _byReal[realName] = token;
    return token;
  }

  /// Returns metadata map for the given [token], or null.
  Map<String, dynamic>? metaFor(String token) {
    final v = _byToken[token];
    if (v == null) return null;
    return Map<String, dynamic>.from(v as Map);
  }

  /// Returns true if [realName] has been mapped.
  bool contains(String realName) => _byReal.containsKey(realName);

  /// Reverse lookup: real name for a given [token].
  String? realFor(String token) {
    final meta = _byToken[token];
    if (meta == null) return null;
    return (meta as Map)['r'] as String?;
  }

  /// Sets extra metadata fields on an existing token entry.
  void setMeta(String token, Map<String, dynamic> fields) {
    final existing = _byToken[token];
    if (existing == null) return;
    (existing as Map).addAll(fields);
  }

  /// Marks a token as deprecated (real name removed from forward index).
  void deprecate(String token) {
    final meta = _byToken[token] as Map?;
    if (meta == null) return;
    final realName = meta['r'] as String?;
    if (realName != null) _byReal.remove(realName);
    meta['deprecated'] = true;
  }

  /// Loads the token map from [path].
  static TokenMap load(String path, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final tm = TokenMap();
    final raw = fileIO.read(path);
    if (raw.isEmpty) return tm;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final token = entry.key;
        final meta = Map<String, dynamic>.from(entry.value as Map);
        tm._byToken[token] = meta;
        final deprecated = meta['deprecated'] as bool? ?? false;
        if (!deprecated) {
          final realName = meta['r'] as String?;
          if (realName != null) tm._byReal[realName] = token;
        }
        // Restore counter
        final colon = token.indexOf(':');
        if (colon >= 0) {
          final prefix = token.substring(0, colon);
          final letter = token.substring(colon + 1);
          final idx = _letterIndex(letter);
          final current = tm._counters[prefix] ?? 0;
          if (idx >= current) tm._counters[prefix] = idx + 1;
        }
      }
    } on FormatException catch (_) {}
    return tm;
  }

  /// Saves the token map to [path].
  void save(String path, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    const encoder = JsonEncoder.withIndent('  ');
    fileIO.write(path, encoder.convert(_byToken));
  }

  String _nextToken(String prefix) {
    final idx = _counters[prefix] ?? 0;
    _counters[prefix] = idx + 1;
    return '$prefix:${_indexToLetters(idx)}';
  }

  static String _indexToLetters(int idx) {
    // A-Z then AA, AB...
    const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (idx < 26) return alpha[idx];
    final high = (idx ~/ 26) - 1;
    final low = idx % 26;
    return '${alpha[high]}${alpha[low]}';
  }

  static int _letterIndex(String letters) {
    const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (letters.length == 1) return alpha.indexOf(letters);
    final high = alpha.indexOf(letters[0]);
    final low = alpha.indexOf(letters[1]);
    return (high + 1) * 26 + low;
  }
}
