// ledger_run.dart — writes the ledger of a mutants run
//
//   dart run tool/proof_audit/ledger_run.dart --root=<repo> --logs=<workspace dir>
//       --out=<markdown file> [--lcov=<tracefile>] [--equivalents=<registry>]
//       [--title=<heading>]

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
  final root = _option(args, 'root') ?? Directory.current.path;
  final logs = _option(args, 'logs') ?? '/tmp/claudart_proof_audit/ws';
  final out = _option(args, 'out')!;
  final lcovPath = _option(args, 'lcov');
  final equivalentsPath = _option(args, 'equivalents');
  final rows = mutantRows([
    for (final line in File(logFilePath('$logs/logs', LogFile.proofs)).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ]);
  final sources = {
    for (final file in {for (final row in rows) row.file})
      file: File('$root/$file').readAsStringSync(),
  };
  File(out).writeAsStringSync(renderLedger(
    rows: rows,
    sources: sources,
    lcov: lcovPath == null ? const {} : lineHits(File(lcovPath).readAsStringSync()),
    root: root,
    title: _option(args, 'title') ?? 'Test ledger',
    equivalents: equivalentsPath == null
        ? const {}
        : parseEquivalents(File(equivalentsPath).readAsStringSync()),
  ));
  stdout.writeln('ledger: $out, from ${rows.length} mutants of ${sources.length} files');
}
