// trace_diagram.dart — what the tests did, drawn
//
// A traced check records what a test gave the code, what it expected, what it
// got, and which log rows it caused (`test/helpers/test_trace.dart`). The
// expectation is recorded before the answer, so a test that only echoes what
// the code returned shows as flagged, and a check with no obligation to anchor
// it is counted as unanchored. This file reads the trace and draws it, as the
// run diagram does for the logs.

import 'dart:convert';

import 'mermaid_page.dart';

/// The anchor of a check that names no spec obligation.
const String unanchoredObligation = 'unanchored';

/// One traced check.
class TraceRow {
  const TraceRow({
    required this.test,
    required this.obligation,
    required this.input,
    required this.expected,
    required this.actual,
    required this.passed,
    required this.expectedAt,
    required this.actualAt,
    this.caused = const [],
  });

  factory TraceRow.fromJson(Map<String, dynamic> json) => TraceRow(
        test: json[_TraceKey.test.name] as String,
        obligation: json[_TraceKey.obligation.name] as String?,
        input: json[_TraceKey.input.name] as String,
        expected: json[_TraceKey.expected.name] as String,
        actual: json[_TraceKey.actual.name] as String,
        passed: json[_TraceKey.passed.name] as bool,
        expectedAt: json[_TraceKey.expectedAt.name] as int,
        actualAt: json[_TraceKey.actualAt.name] as int,
        caused: [
          for (final row in json[_TraceKey.caused.name] as List<dynamic>)
            row as String,
        ],
      );

  final String test;

  /// The name of the spec obligation the check belongs to, or null.
  final String? obligation;
  final String input;
  final String expected;
  final String actual;
  final bool passed;

  /// The order in which the expectation and the answer were recorded.
  final int expectedAt;
  final int actualAt;

  /// The log rows the check caused, as text.
  final List<String> caused;

  /// Whether the expectation was recorded before the answer.
  bool get expectedFirst => expectedAt < actualAt;

  /// The obligation, or [unanchoredObligation].
  String get anchor => obligation ?? unanchoredObligation;

  Map<String, dynamic> toJson() => {
        _TraceKey.test.name: test,
        _TraceKey.obligation.name: obligation,
        _TraceKey.input.name: input,
        _TraceKey.expected.name: expected,
        _TraceKey.actual.name: actual,
        _TraceKey.passed.name: passed,
        _TraceKey.expectedAt.name: expectedAt,
        _TraceKey.actualAt.name: actualAt,
        _TraceKey.caused.name: caused,
      };
}

/// The keys of a trace row's JSON; the names are the keys.
enum _TraceKey {
  test,
  obligation,
  input,
  expected,
  actual,
  passed,
  expectedAt,
  actualAt,
  caused,
}

/// The rows of a trace file: each JSON line that is a trace row. Anything else
/// is skipped, so one bad line does not hide the rest.
List<TraceRow> traceRowsOfJsonl(String text) {
  final rows = <TraceRow>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) rows.add(TraceRow.fromJson(decoded));
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }
  }
  return rows;
}

String _safe(String text) {
  final cleaned = text
      .replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ')
      .replaceAll(';', ',')
      .replaceAll('#', '');
  return cleaned.length > 120 ? '${cleaned.substring(0, 119)}…' : cleaned;
}

/// The Mermaid sequence diagram of one traced check.
String renderTraceDiagram(TraceRow row) => [
      'sequenceDiagram',
      '    participant Test',
      '    participant Code',
      '    Note over Test: expected ${_safe(row.expected)}',
      '    Test->>Code: ${_safe(row.input)}',
      '    Code-->>Test: ${_safe(row.actual)}',
      for (final line in row.caused) '    Note over Code: caused ${_safe(line)}',
      if (!row.expectedFirst)
        '    Note over Test: ⚠ the expectation was recorded after the answer',
      row.passed
          ? '    Note over Test: ✓ matches'
          : '    Note over Test: ✗ differs from the expectation',
      '',
    ].join('\n');

/// A markdown page: a count of the checks for each obligation, then a heading
/// and a fenced diagram for each check.
String renderTracePage(List<TraceRow> rows) {
  if (rows.isEmpty) return '# Traced checks\n\nNo checks were traced.\n';
  final byAnchor = <String, List<TraceRow>>{};
  for (final row in rows) {
    byAnchor.putIfAbsent(row.anchor, () => []).add(row);
  }
  final buffer = StringBuffer('# Traced checks\n\n')
    ..writeln('| obligation | checks | passed |')
    ..writeln('|---|---|---|');
  for (final entry in byAnchor.entries) {
    buffer.writeln('| ${entry.key} | ${entry.value.length} | '
        '${entry.value.where((row) => row.passed).length} |');
  }
  for (final row in rows) {
    buffer
      ..writeln()
      ..writeln('## ${row.test} — ${row.anchor}')
      ..writeln()
      ..writeln('```mermaid')
      ..write(renderTraceDiagram(row))
      ..writeln('```');
  }
  return buffer.toString();
}

/// A web page that draws each traced check. What a test wrote is escaped.
String renderTraceHtml(List<TraceRow> rows) => renderMermaidHtml(
      pageTitle: 'claudart traced checks',
      heading: 'Traced checks',
      emptyText: 'No checks were traced.',
      sections: [
        for (final row in rows)
          (
            heading: '${row.test} — ${row.anchor}',
            diagram: renderTraceDiagram(row),
          ),
      ],
    );
