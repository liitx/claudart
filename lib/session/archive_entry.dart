// archive_entry.dart — typed record of a completed or paused session.
//
// Written to archive/index.json by `claudart teardown`.
// Read by `claudart archives` and zedup's archive list screen.
//
// ArchiveKind.archive  — session resolved; skills updated; full teardown done.
// ArchiveKind.reminder — session paused; no skills update; resume later.

import 'dart:convert';

enum ArchiveKind {
  archive,
  reminder;

  String get label => name;

  static ArchiveKind fromString(String s) =>
      ArchiveKind.values.firstWhere((v) => v.name == s,
          orElse: () => ArchiveKind.archive);
}

class ArchiveEntry {
  final String      id;
  final ArchiveKind kind;
  final String      description;
  final String      branch;
  final DateTime    createdAt;
  /// Filename (relative to archive/) of the handoff snapshot.
  final String      handoffFile;
  /// Non-empty when skills.md was updated (archive kind only).
  final String?     skillsDelta;

  const ArchiveEntry({
    required this.id,
    required this.kind,
    required this.description,
    required this.branch,
    required this.createdAt,
    required this.handoffFile,
    this.skillsDelta,
  });

  factory ArchiveEntry.fromJson(Map<String, dynamic> json) => ArchiveEntry(
        id:           json['id']          as String,
        kind:         ArchiveKind.fromString(json['kind'] as String),
        description:  json['description'] as String,
        branch:       json['branch']      as String,
        createdAt:    DateTime.parse(json['createdAt'] as String),
        handoffFile:  json['handoffFile'] as String,
        skillsDelta:  json['skillsDelta'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id':          id,
        'kind':        kind.label,
        'description': description,
        'branch':      branch,
        'createdAt':   createdAt.toIso8601String(),
        'handoffFile': handoffFile,
        if (skillsDelta != null) 'skillsDelta': skillsDelta,
      };
}

// ── Index helpers ─────────────────────────────────────────────────────────────

List<ArchiveEntry> archiveEntriesFromJson(String raw) {
  if (raw.trim().isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(ArchiveEntry.fromJson)
        .toList();
  } on FormatException {
    return [];
  }
}

String archiveEntriesToJson(List<ArchiveEntry> entries) =>
    const JsonEncoder.withIndent('  ').convert(
      entries.map((e) => e.toJson()).toList(),
    );
