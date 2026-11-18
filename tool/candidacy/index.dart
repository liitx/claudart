// index.dart — one page that answers, for any postulate: what is it, where does it
// stand, what proves it, and how it got there.
//
//   dart run tool/candidacy/index.dart     (writes docs/candidacy/index.md)
//
// Read from the candidate ledger and nothing else, so the page cannot disagree with
// it: a test regenerates it and fails when the file differs. An agent reads this
// instead of the ledger or the method document.

import 'dart:io';

import 'package:dartrix/dartrix.dart';

/// Where the index is written.
const candidacyIndexPath = 'docs/candidacy/index.md';

/// Where the ledger it is read from is kept.
const _ledgerPath = 'docs/candidacy/ledger.jsonl';

/// The index of [ledger]: counts by status, the candidates flagged as stalled or
/// dropped, then one block per candidate in the order each first appeared.
String renderCandidateIndex(CandidateLedger ledger) {
  final ids = <String>[];
  for (final entry in ledger.entries) {
    if (!ids.contains(entry.candidateId)) ids.add(entry.candidateId);
  }
  final buffer = StringBuffer()
    ..writeln('# Candidate index')
    ..writeln()
    ..writeln('Generated from `docs/candidacy/ledger.jsonl` by '
        '`dart run tool/candidacy/index.dart`; a test fails when it differs. '
        'Confidence is under the initial weights, which are an assumption.')
    ..writeln()
    ..writeln('## By status')
    ..writeln();
  for (final status in CandidateStatus.values) {
    final named = [for (final id in ids) if (ledger.statusOf(id) == status) id];
    buffer.writeln('- ${status.name}: ${named.isEmpty ? 'none' : named.join(', ')}');
  }
  buffer
    ..writeln()
    ..writeln('Flagged (confidence stalled or dropped): '
        '${ledger.flagged.isEmpty ? 'none' : ledger.flagged.join(', ')}');
  for (final id in ids) {
    final history = [for (final e in ledger.entries) if (e.candidateId == id) e];
    final first = history.first;
    final latest = history.last;
    final confidence = latest.confidenceUnder(ledger.weights);
    buffer
      ..writeln()
      ..writeln('## $id: ${latest.status.name}')
      ..writeln()
      ..writeln('- Statement: ${first.justification}')
      ..writeln('- Spec: ${latest.specReference}')
      ..writeln('- Mocks: ${latest.mockDatasetVersion}')
      ..writeln('- Variants covered: ${latest.variantsCovered.length} of '
          '${latest.variantsInSpec.length}')
      ..writeln('- Boundary: ${latest.boundary ?? 'not stated'}')
      ..writeln('- Confidence: '
          '${confidence == null ? 'none' : confidence.toStringAsFixed(2)}')
      ..writeln('- History: ${history.map((e) => e.status.name).join(' -> ')}')
      ..writeln('- Evidence:');
    for (final citation in latest.evidence) {
      buffer.writeln('  - $citation');
    }
    if (latest.evidence.isEmpty) buffer.writeln('  - none');
  }
  return buffer.toString();
}

void main() {
  final parsed = CandidateLedger.parse(File(_ledgerPath).readAsStringSync());
  File(candidacyIndexPath).writeAsStringSync(renderCandidateIndex(parsed.ledger));
  stdout.writeln('index of ${parsed.ledger.entries.length} entries -> $candidacyIndexPath');
}
