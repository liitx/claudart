// pending_confirmation.dart — durable, workspace-scoped confirmation state
//
// Tracks a confirmation gate (see pipeline/agents/confirmation.dart) across
// the stateless-per-call boundary any consumer (zedup, a future IDE panel)
// dispatches through. Lives alongside handoff.md/skills.md in the workspace
// directory — not local UI state — so every consumer reading the same
// workspace sees the same pending confirmation, durable across restarts.
//
// Deliberately separate from HandoffStatus: workflow phase (suggest vs.
// debug vs. done) and "a confirmation is pending right now" are orthogonal
// axes. Conflating them into one enum would force every consumer parsing
// `## Status` to also guess which axis a value belongs to.

import 'dart:convert';
import '../io/file_io.dart';
import '../config/paths.dart';

/// A confirmation gate awaiting the user's reply, persisted to
/// `pending_confirmation.json` in the workspace directory.
class PendingConfirmation {
  /// What was asked — shown back to the user if a consumer needs to
  /// re-display context (e.g. after a restart).
  final String question;

  /// The claudart CLI command to run when the user's reply classifies as
  /// [ConfirmationOption.confirm]. E.g. `'claudart save'`.
  final String onConfirmCommand;

  /// When this confirmation was raised. Consumers may use this to expire
  /// stale confirmations (e.g. from a crashed session) rather than acting
  /// on a prompt the user never actually saw.
  final DateTime createdAt;

  const PendingConfirmation({
    required this.question,
    required this.onConfirmCommand,
    required this.createdAt,
  });

  factory PendingConfirmation.fromJson(Map<String, dynamic> json) =>
      PendingConfirmation(
        question: json['question'] as String,
        onConfirmCommand: json['onConfirmCommand'] as String,
        // .toUtc() normalizes at the deserialization boundary: a
        // timezone-less stored string parses as local time, which would
        // shift the instant if a consumer reads this durable file under a
        // different TZ than the one that wrote it.
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'onConfirmCommand': onConfirmCommand,
        // .toUtc() so the ISO-8601 string always carries a 'Z' suffix —
        // unambiguous regardless of which consumer's local TZ wrote it.
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

/// Reads/writes/clears [PendingConfirmation] for a workspace. All
/// operations are injectable via [FileIO] — no direct disk I/O, matching
/// every other session file in this package.
abstract final class PendingConfirmationStore {
  /// Returns the pending confirmation for [workspace], or null when none
  /// is set or the file is missing/corrupt. Never throws — a corrupt file
  /// is treated the same as no pending confirmation, since acting on
  /// malformed state is worse than asking again.
  static PendingConfirmation? load(String workspace, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final path = pendingConfirmationPathFor(workspace);
    if (!fileIO.fileExists(path)) return null;
    try {
      final raw = fileIO.read(path);
      if (raw.isEmpty) return null;
      return PendingConfirmation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      // Broad catch is deliberate: fileIO.read can throw a real IO error
      // (e.g. the file existed at the check above but was deleted/became
      // unreadable before this read — a genuine TOCTOU race, not
      // hypothetical), missing/wrong-typed fields throw TypeError (an
      // Error, not an Exception), and malformed JSON throws
      // FormatException. All three must resolve to "no pending
      // confirmation" — this method's contract is that it never throws.
      return null;
    }
  }

  /// Persists [confirmation] for [workspace], overwriting any existing one.
  static void write(
    String workspace,
    PendingConfirmation confirmation, {
    FileIO? io,
  }) {
    final fileIO = io ?? const RealFileIO();
    const encoder = JsonEncoder.withIndent('  ');
    fileIO.write(
      pendingConfirmationPathFor(workspace),
      encoder.convert(confirmation.toJson()),
    );
  }

  /// Removes any pending confirmation for [workspace]. A no-op when none
  /// exists.
  static void clear(String workspace, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final path = pendingConfirmationPathFor(workspace);
    if (fileIO.fileExists(path)) fileIO.delete(path);
  }
}
