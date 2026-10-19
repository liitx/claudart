// hook.dart — `claudart hook pre-edit`: how Claude Code is bound to the
// claudart workflow, as compiled and tested code instead of a shell string.
//
// Claude Code runs this before each Edit, Write and MultiEdit (the command is
// written into the project's .claude/settings.json by `claudart link`). It
// reads the tool call from stdin, finds the linked project the edited file
// belongs to, and answers from that project's session:
//   - not a Dart source file, no linked project, or the session is ready to
//     implement (canStartDebug): silent, the edit goes ahead;
//   - otherwise: advise, or deny when the workspace is strict (owner.strict).
// Advise adds context Claude sees; deny blocks the edit with the reason.
// It always exits 0: a hook that fails must never block work by accident.
//
// No `git` process is spawned (this runs on every edit): the project is found
// by matching the file path against the registry's project roots.

import 'dart:convert';
import 'dart:io';

import '../file_io.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/session_state.dart';
import '../workspace/workspace_config.dart';

/// What the pre-edit hook decides.
enum HookOutcome {
  /// Let the edit through without a word.
  silent,

  /// Let it through, and tell Claude the session is not ready for it.
  advise,

  /// Block it, and tell Claude why.
  deny;

  /// The text Claude sees; null when there is nothing to say.
  String? messageFor({
    required String projectName,
    required HandoffStatus status,
  }) =>
      switch (this) {
        HookOutcome.silent => null,
        HookOutcome.advise =>
          'claudart session for $projectName is ${status.value}, so this '
              'change is not going through the session. Implement code '
              'through /debug (it needs ready-for-debug or debug-in-progress; '
              'run /suggest then /save first) and checkpoint with /save. '
              'Other linked sessions: claudart workspaces.',
        HookOutcome.deny =>
          'Blocked: claudart session for $projectName is ${status.value} and '
              'this workspace is strict. Run /suggest then /save to reach '
              'ready-for-debug, then implement through /debug.',
      };
}

/// The decision, from the three facts that determine it.
HookOutcome decidePreEdit({
  required bool isDartSource,
  required HandoffStatus status,
  required bool strict,
}) {
  if (!isDartSource || status.canStartDebug) return HookOutcome.silent;
  return strict ? HookOutcome.deny : HookOutcome.advise;
}

/// The words of Claude Code's hook protocol (PreToolUse). The keys are the
/// protocol's own, so the enum names are written as-is.
enum HookResponseField {
  hookSpecificOutput,
  hookEventName,
  permissionDecision,
  permissionDecisionReason,
  additionalContext;
}

abstract final class HookWire {
  static const preToolUse = 'PreToolUse';
  static const denyDecision = 'deny';
  static const dartSourceSuffix = '.dart';
  static const preEditSubcommand = 'pre-edit';
}

/// The JSON to print for [outcome]; null for [HookOutcome.silent].
String? preEditResponseJson(HookOutcome outcome, String? message) {
  if (outcome == HookOutcome.silent || message == null) return null;
  return jsonEncode({
    HookResponseField.hookSpecificOutput.name: {
      HookResponseField.hookEventName.name: HookWire.preToolUse,
      if (outcome == HookOutcome.deny) ...{
        HookResponseField.permissionDecision.name: HookWire.denyDecision,
        HookResponseField.permissionDecisionReason.name: message,
      } else
        HookResponseField.additionalContext.name: message,
    },
  });
}

/// The stdin fields of a PreToolUse call that this hook reads.
enum HookInputField {
  toolInput('tool_input'),
  filePath('file_path');

  const HookInputField(this.wireKey);

  final String wireKey;
}

/// The edited file's path from the hook's stdin JSON, or null when the input
/// is not the expected shape (a hook must tolerate anything).
String? editedFilePath(String stdinText) {
  try {
    final decoded = jsonDecode(stdinText);
    if (decoded is! Map<String, dynamic>) return null;
    final toolInput = decoded[HookInputField.toolInput.wireKey];
    if (toolInput is! Map<String, dynamic>) return null;
    final path = toolInput[HookInputField.filePath.wireKey];
    return path is String && path.isNotEmpty ? path : null;
  } on FormatException {
    return null;
  }
}

/// The linked project that [filePath] is inside: the deepest matching project
/// root, so nested checkouts resolve to the inner one.
RegistryEntry? entryContaining(Registry registry, String filePath) {
  RegistryEntry? best;
  for (final entry in registry.entries) {
    final root = entry.projectRoot;
    final inside = filePath == root || filePath.startsWith('$root/');
    if (inside && (best == null || root.length > best.projectRoot.length)) {
      best = entry;
    }
  }
  return best;
}

/// Runs the pre-edit hook for one Claude Code call. Prints the response (if
/// any) to [out] and never throws.
void runHook({
  required String stdinText,
  FileIO? io,
  StringSink? out,
}) {
  try {
    final fileIO = io ?? const RealFileIO();
    final filePath = editedFilePath(stdinText);
    if (filePath == null) return;
    final entry = entryContaining(Registry.load(io: fileIO), filePath);
    if (entry == null) return;

    final handoff = handoffPathFor(entry.workspacePath);
    final status = SessionState.parse(
      fileIO.fileExists(handoff) ? fileIO.read(handoff) : '',
    ).effectiveStatus;
    final strict =
        WorkspaceConfig.load(entry.workspacePath, io: fileIO)?.owner.strict ??
            false;

    final outcome = decidePreEdit(
      isDartSource: filePath.endsWith(HookWire.dartSourceSuffix),
      status: status,
      strict: strict,
    );
    final json = preEditResponseJson(
      outcome,
      outcome.messageFor(projectName: entry.name, status: status),
    );
    if (json != null) (out ?? stdout).writeln(json);
  } on Object {
    // A failing hook must not block the edit it was asked about.
  }
}
