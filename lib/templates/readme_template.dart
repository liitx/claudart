// readme_template.dart — README.md's machine-owned Roadmap block
//
// Pure function, no I/O — same style as claude_template.dart. Output is
// spliced into an existing README.md by link.dart (everything above the
// `<!-- claudart:link:roadmap -->` marker, including the `## Roadmap`
// heading and its TOC anchor, is preserved untouched); never written as a
// whole file on its own.
//
// Row data is caller-assembled (link.dart reads a project-root `roadmap.json`
// via parseRoadmapConfig), not parsed from PLAN.md — PLAN.md's phase headers
// aren't uniformly structured for automated extraction. `roadmap.json` is
// git-committed (unlike workspace.json, which lives outside the repo
// entirely and can't be a source a fresh clone or CI could ever verify
// against). This template only renders whatever it's given; filtering
// deferred/parked content out of what should even be rendered is the
// caller's responsibility, same discipline plan_template.dart already uses
// for PLAN.md stub sections.

import 'dart:convert';

/// One row of the Roadmap table. `status` carries the full display string
/// (e.g. `shipped`, `deferred, see PLAN.md`) — this template does not
/// interpret it.
typedef RoadmapRow = ({String phase, String scope, String status});

/// A project's full `roadmap.json` content. `summaryText`/`footerLine` are
/// optional because most projects (e.g. claudart's own) are fine with the
/// generic defaults — only a project with existing custom copy (e.g.
/// dartrix's "Six phases — current ship is schema v3 + visual polish"
/// summary and its "Deep dive" link line) needs to set them, to avoid the
/// splice silently overwriting content that has no other source.
typedef RoadmapConfig = ({
  String? summaryText,
  String? footerLine,
  List<RoadmapRow> rows,
});

/// Parses a project's `roadmap.json` — a JSON object with a required `rows`
/// array of `{"phase", "scope", "status"}` objects, plus optional
/// `summaryText`/`footerLine` strings — into a [RoadmapConfig]. Returns null
/// on missing/malformed content — same "absent means not opted in" contract
/// as `WorkspaceConfig.load`, not an exception, since a project without
/// `roadmap.json` is the common case, not an error.
RoadmapConfig? parseRoadmapConfig(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final rawRows = decoded['rows'];
    if (rawRows is! List) return null;
    return (
      summaryText: decoded['summaryText'] as String?,
      footerLine: decoded['footerLine'] as String?,
      rows: rawRows.map((r) {
        final row = r as Map<String, dynamic>;
        return (
          phase: row['phase'] as String,
          scope: row['scope'] as String,
          status: row['status'] as String,
        );
      }).toList(),
    );
  } on FormatException {
    return null;
  }
}

/// `<projectRoot>/roadmap.json` — the opt-in source [parseRoadmapConfig]
/// reads from. Shared by `link.dart`'s write path and
/// `artifact_state.dart`'s read-only staleness check.
const String kRoadmapJsonFilename = 'roadmap.json';

/// `<projectRoot>/README.md` — the file [readmeTemplate]'s output is
/// spliced into. Shared the same way as [kRoadmapJsonFilename].
const String kReadmeFilename = 'README.md';

/// [readmeTemplate]'s default `summaryText` when a project's
/// `roadmap.json` doesn't set its own.
const String kDefaultRoadmapSummaryText = "What's coming";

/// The marker `readmeTemplate`'s output always starts with — the splice
/// point between the README's hand-curated `## Roadmap` heading (preserved,
/// keeps its TOC anchor) and the machine-owned table below it. Stops before
/// the next `---` section separator (not the next `## ` heading) — every
/// top-level README section is followed by a `---` rule before the next
/// heading, and stopping at `## ` instead would consume that separator,
/// visibly joining Roadmap to the following section. Unlike
/// `claude_template.dart`'s `generatedMarker`, this splice is opt-in: a
/// README.md without this marker is left untouched entirely, since (unlike
/// CLAUDE.md) README.md is not a claudart-owned file for every project.
///
/// `(?![\s\S])` is "end of input," not `\z` — Dart/JS regex has no `\z`
/// metacharacter (that's Perl/Python syntax); in ECMAScript-flavored regex
/// `\z` is silently a literal lowercase `z`. Using it here made the splice
/// stop at the first `z` in the roadmap content instead of the end of
/// input — worked by luck against claudart's own roadmap text (no `z`
/// appears in it), corrupted the first live run against a project whose
/// roadmap text contained "zedup," caught and fixed before landing.
final RegExp roadmapMarker = RegExp(
    r'^<!-- claudart:link:roadmap -->.*?(?=\n---|(?![\s\S]))',
    multiLine: true,
    dotAll: true);

String readmeTemplate({
  required List<RoadmapRow> roadmapRows,
  String summaryText = kDefaultRoadmapSummaryText,
  String? footerLine,
}) {
  final rows = roadmapRows
      .map((r) => '| ${r.phase} | ${r.scope} | ${r.status} |')
      .join('\n');
  final footer = footerLine != null ? '\n$footerLine\n' : '';

  return '''<!-- claudart:link:roadmap -->
<details>
<summary><strong>$summaryText</strong></summary>

| Phase | Scope | Status |
|---|---|---|
$rows
$footer
</details>
''';
}
