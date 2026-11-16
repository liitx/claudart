// evidence_audit.dart — derive a Phase 0 outcome from the line ledger's rows,
// instead of setting it by reading.
//
//   dart run tool/candidacy/evidence_audit.dart --logs=<workspace dir>
//
// Reads the mutant rows a line-ledger run wrote (`make ledger`, or
// `run.dart --mutants=<file>`) and keeps, for every `lib/` line a candidate in
// docs/candidacy/ledger.jsonl cites, the verdict of each one-line mutant. The
// snapshot goes to docs/candidacy/evidence_rows.jsonl. A test compares what a
// ledger entry says about `everyTestCanFail` with what the snapshot derives, and
// fails when a cited line has changed since the snapshot.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/logger.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:dartrix/dartrix.dart';

import '../proof_audit/controls.dart' show controlProof;


/// Separates a cited file from the text it must contain.
const citationSeparator = ' :: ';

/// Where the snapshot of mutant rows for cited lines is kept.
const evidenceRowsPath = 'docs/candidacy/evidence_rows.jsonl';

/// Where the candidate ledger is kept.
const candidateLedgerPath = 'docs/candidacy/ledger.jsonl';

/// One verdict of the audit about one line: a one-line mutant of the line ledger
/// or a single-fact fault of a matrix audit.
typedef EvidenceRow = ({
  String proof,
  String file,
  int line,
  String description,
  ProofVerdict verdict,
});

/// The audit rows of a proofs log, the latest verdict of each fault. Controls
/// are the audit checking itself and are not evidence about a line.
List<EvidenceRow> evidenceRows(List<Map<String, dynamic>> logged) {
  final latest = <String, EvidenceRow>{};
  for (final row in logged) {
    final proof = row[LogEntryField.proof.name] as String;
    if (proof == controlProof) continue;
    final description = row[LogEntryField.fault.name] as String;
    latest['$proof|$description'] = (
      proof: proof,
      file: row[LogEntryField.sourceFile.name] as String,
      line: row[LogEntryField.sourceLine.name] as int,
      description: description,
      verdict: ProofVerdict.values.byName(row[LogEntryField.verdict.name] as String),
    );
  }
  return latest.values.toList();
}

/// The `lib/` lines a citation points at: every line of the file that contains
/// the cited text. A citation outside `lib/` cites no line of code.
List<({String file, int line, String text})> citedLines(
  String citation,
  String Function(String path) readFile,
) {
  final parts = citation.split(citationSeparator);
  final path = parts.first;
  if (!path.startsWith('lib/')) return const [];
  final needle = parts.sublist(1).join(citationSeparator);
  final lines = readFile(path).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].contains(needle)) (file: path, line: i + 1, text: lines[i]),
  ];
}

/// What the mutants of the cited lines say about whether the tests can fail.
/// Written out so a change to a rule fails a test:
/// - no row, or only rows no test run could judge: not checked;
/// - a mutant that no test failed on: failed;
/// - otherwise every judged mutant was caught: passed.
ProofAuditOutcome everyTestCanFailFrom(List<EvidenceRow> rows) {
  final judged = rows.where((r) => r.verdict != ProofVerdict.invalid);
  if (judged.isEmpty) return ProofAuditOutcome.notChecked;
  if (judged.any((r) => r.verdict == ProofVerdict.missed)) {
    return ProofAuditOutcome.failed;
  }
  return ProofAuditOutcome.passed;
}

/// The rows that sit on one of [cited].
List<EvidenceRow> rowsOnCitedLines(
  List<EvidenceRow> rows,
  List<({String file, int line, String text})> cited,
) =>
    [
      for (final row in rows)
        if (cited.any((c) => c.file == row.file && c.line == row.line)) row,
    ];

void main(List<String> args) {
  final logs = args
      .firstWhere((a) => a.startsWith('--logs='))
      .substring('--logs='.length);
  final parsed = CandidateLedger.parse(File(candidateLedgerPath).readAsStringSync());
  final cited = [
    for (final entry in parsed.ledger.entries)
      for (final citation in entry.evidence)
        ...citedLines(citation, (p) => File(p).readAsStringSync()),
  ];
  final rows = evidenceRows([
    for (final line in File(logFilePath('$logs/logs', LogFile.proofs)).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ]);
  final kept = rowsOnCitedLines(rows, cited);
  final out = [
    for (final row in kept)
      jsonEncode({
        'proof': row.proof,
        'file': row.file,
        'line': row.line,
        'lineText': cited
            .firstWhere((c) => c.file == row.file && c.line == row.line)
            .text,
        'description': row.description,
        'verdict': row.verdict.name,
      }),
  ]..sort();
  File(evidenceRowsPath).writeAsStringSync('${out.join('\n')}\n');
  stdout.writeln('${kept.length} audit rows on ${cited.length} cited lines -> $evidenceRowsPath');
}
