// claude_settings_env.dart — reads ~/.claude/settings.json's own `env` block
//
// Confirmed against a real Bedrock machine: Bedrock env vars can live
// ONLY in ~/.claude/settings.json's top-level `env` object, never exported
// to the parent shell at all — `claude` itself reads this file directly.
// AgentProvider.detect alone (process-env only) reports a false negative
// in exactly that case. This reads the same source `claude` reads, so
// detection can see what `claude` sees instead of only what the shell does.
//
// Defensive by design: any parse failure (missing file, malformed JSON,
// an `env` key that's absent or not a flat string-keyed object) returns
// {} rather than throwing — a settings.json claudart can't parse must
// never crash detection, only fall back to process-env-only behavior.

import 'dart:convert';
import 'dart:io' show Platform;

import '../file_io.dart';

/// `~/.claude/settings.json` — resolved fresh each call so a test override
/// of `HOME` is honored without a cached stale path.
String get defaultClaudeSettingsPath {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/.claude/settings.json';
}

/// Reads the `env` object out of `~/.claude/settings.json` (or [path] when
/// given). Returns an empty map for any failure.
Map<String, String> readClaudeSettingsEnv({
  FileIO? io,
  String? path,
}) {
  final fileIO = io ?? const RealFileIO();
  final settingsPath = path ?? defaultClaudeSettingsPath;
  if (!fileIO.fileExists(settingsPath)) return {};
  try {
    final decoded = jsonDecode(fileIO.read(settingsPath));
    if (decoded is! Map) return {};
    final env = decoded['env'];
    if (env is! Map) return {};
    return {
      for (final entry in env.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  } on FormatException {
    return {};
  }
}
