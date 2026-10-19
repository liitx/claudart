// claude_settings_template.dart — the part of a project's
// `.claude/settings.json` that claudart owns.
//
// `claudart link` merges two things into the file and leaves everything else
// as the user wrote it:
//   - a PreToolUse hook on Edit, Write and MultiEdit that runs
//     `claudart hook pre-edit` (what binds Claude Code to the session), and
//   - CLAUDART_DEBUG=1 in `env`, so claudart calls made from that project's
//     Claude Code sessions write the per-step trace.
// The hook is found again by its command, so re-running link updates it in
// place instead of adding a second one. A value the user already set for the
// env var is left alone.

import 'dart:convert';

import '../commands/hook.dart' show HookWire;
import '../pipeline/debug_mode.dart'
    show kClaudartDebugEnabledValue, kClaudartDebugEnvVar;

/// The keys of Claude Code's settings.json that this file reads and writes.
enum ClaudeSettingsKey {
  hooks('hooks'),
  preToolUse('PreToolUse'),
  matcher('matcher'),
  type('type'),
  command('command'),
  env('env');

  const ClaudeSettingsKey(this.wireKey);

  final String wireKey;
}

abstract final class ClaudeSettingsWire {
  /// The tools the hook runs before.
  static const editToolsMatcher = 'Edit|Write|MultiEdit';
  static const commandHookType = 'command';

  /// The command claudart owns; also how its entry is found again.
  static const hookCommand = 'claudart hook ${HookWire.preEditSubcommand}';
}

Map<String, Object?> _managedHookEntry() => {
      ClaudeSettingsKey.matcher.wireKey: ClaudeSettingsWire.editToolsMatcher,
      ClaudeSettingsKey.hooks.wireKey: [
        {
          ClaudeSettingsKey.type.wireKey: ClaudeSettingsWire.commandHookType,
          ClaudeSettingsKey.command.wireKey: ClaudeSettingsWire.hookCommand,
        },
      ],
    };

bool _isManagedEntry(Object? entry) {
  if (entry is! Map) return false;
  final hooks = entry[ClaudeSettingsKey.hooks.wireKey];
  return hooks is List &&
      hooks.any(
        (hook) =>
            hook is Map &&
            hook[ClaudeSettingsKey.command.wireKey] ==
                ClaudeSettingsWire.hookCommand,
      );
}

bool _entryMatchesManaged(Object? entry) =>
    jsonEncode(entry) == jsonEncode(_managedHookEntry());

Map<String, dynamic> _parse(String existing) {
  if (existing.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(existing);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('settings.json is not a JSON object');
  }
  return decoded;
}

/// [existing] (a settings.json's text, '' for none) with claudart's hook and
/// env entry added or updated. Everything else is kept. Throws
/// [FormatException] when [existing] is not a JSON object, so the caller can
/// leave a file it cannot read alone.
String mergeClaudeSettings(String existing) {
  final settings = _parse(existing);

  final hooks = Map<String, dynamic>.from(
    settings[ClaudeSettingsKey.hooks.wireKey] as Map? ?? {},
  );
  final preToolUse = List<Object?>.from(
    hooks[ClaudeSettingsKey.preToolUse.wireKey] as List? ?? [],
  );
  final at = preToolUse.indexWhere(_isManagedEntry);
  if (at >= 0) {
    preToolUse[at] = _managedHookEntry();
  } else {
    preToolUse.add(_managedHookEntry());
  }
  hooks[ClaudeSettingsKey.preToolUse.wireKey] = preToolUse;
  settings[ClaudeSettingsKey.hooks.wireKey] = hooks;

  final env = Map<String, dynamic>.from(
    settings[ClaudeSettingsKey.env.wireKey] as Map? ?? {},
  );
  env.putIfAbsent(kClaudartDebugEnvVar, () => kClaudartDebugEnabledValue);
  settings[ClaudeSettingsKey.env.wireKey] = env;

  return '${const JsonEncoder.withIndent('  ').convert(settings)}\n';
}

/// Whether [existing] already holds claudart's hook exactly as it would be
/// written and the debug env var. A file that is not a JSON object is stale.
bool claudeSettingsAreFresh(String existing) {
  try {
    final settings = _parse(existing);
    final hooks = settings[ClaudeSettingsKey.hooks.wireKey];
    final preToolUse = hooks is Map
        ? hooks[ClaudeSettingsKey.preToolUse.wireKey]
        : null;
    final env = settings[ClaudeSettingsKey.env.wireKey];
    return preToolUse is List &&
        preToolUse.where(_isManagedEntry).length == 1 &&
        preToolUse.where(_isManagedEntry).every(_entryMatchesManaged) &&
        env is Map &&
        env.containsKey(kClaudartDebugEnvVar);
  } on FormatException {
    return false;
  }
}
