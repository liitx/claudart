// impact.dart — which tests to update when a line changes
//
//   dart run tool/proof_audit/impact.dart --logs=<workspace dir> <file>:<line> [...]
//
// Reads the mutant rows of a ledger run. For each line it names the tests that
// fail when the line is wrong (change the line, update those tests, add none),
// or says no test does and which tests guard the rest of the declaration.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/log_file.dart';

import 'ledger.dart';

void main(List<String> args) {
  final logs = args
      .firstWhere((a) => a.startsWith('--logs='), orElse: () => '--logs=/tmp/claudart_full_ledger/ws')
      .substring('--logs='.length);
  final root = args
      .where((a) => a.startsWith('--root='))
      .map((a) => a.substring('--root='.length))
      .firstOrNull ?? Directory.current.path;
  final rows = mutantRows([
    for (final line in File(logFilePath('$logs/logs', LogFile.proofs)).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ]);
  for (final target in args.where((a) => !a.startsWith('--'))) {
    final parts = target.split(':');
    final file = parts.first;
    final lines = File('$root/$file').readAsStringSync().split('\n');
    stdout.writeln(describeImpact(rows, file, int.parse(parts.last), lines));
  }
}
