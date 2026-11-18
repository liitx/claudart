// ledger_check.dart — the survivors may not grow
//
//   dart run tool/proof_audit/ledger_check.dart --logs=<workspace dir>
//       --baseline=<file> [--equivalents=<registry>] [--write]
//
// Counts the unaccepted surviving mutants of a full ledger run by file and
// compares them with the checked-in baseline. A file with more survivors than
// its baseline fails (exit 1); a file with fewer is reported, and `--write`
// writes the lower counts down, so the debt only ever shrinks and a new file
// starts at zero.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/log_file.dart';

import 'ledger.dart';

String? _option(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}

void main(List<String> args) {
  final logs = _option(args, 'logs') ?? '/tmp/claudart_full_ledger/ws';
  final baselinePath = _option(args, 'baseline') ?? 'docs/topology/ledger/claudart_survivors.txt';
  final equivalentsPath = _option(args, 'equivalents') ?? 'tool/proof_audit/accepted_equivalents.txt';
  final rows = mutantRows([
    for (final line in File(logFilePath('$logs/logs', LogFile.proofs)).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ]);
  final equivalents = File(equivalentsPath).existsSync()
      ? parseEquivalents(File(equivalentsPath).readAsStringSync())
      : <String, String>{};
  final current = survivorsByFile(rows, equivalents);
  final baseline = File(baselinePath).existsSync()
      ? parseBaseline(File(baselinePath).readAsStringSync())
      : <String, int>{};
  final result = compareToBaseline(current, baseline);
  for (final entry in result.improvements.entries) {
    stdout.writeln('better: ${entry.key} ${entry.value.before} -> ${entry.value.now}');
  }
  for (final entry in result.regressions.entries) {
    stdout.writeln('WORSE:  ${entry.key} ${entry.value.before} -> ${entry.value.now}');
  }
  if (args.contains('--write') || !File(baselinePath).existsSync()) {
    // Never write a count higher than the baseline already holds.
    final merged = {
      for (final file in {...current.keys, ...baseline.keys})
        file: baseline.containsKey(file)
            ? (current[file] ?? 0) < baseline[file]! ? (current[file] ?? 0) : baseline[file]!
            : current[file] ?? 0,
    };
    File(baselinePath).writeAsStringSync(renderBaseline(merged));
    stdout.writeln('baseline written: $baselinePath');
  }
  stdout.writeln('${current.values.fold<int>(0, (a, b) => a + b)} survivors in '
      '${current.length} files; ${result.regressions.length} files worse');
  if (result.regressions.isNotEmpty) exit(1);
}
