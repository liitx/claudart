// run.dart — audits the proofs against seeded faults and logs what it finds
//
//   dart run tool/proof_audit/run.dart [--workers=N] [--limit=N] [--only=text]
//       [--proof=name] [--skip-controls] [--report-only] [--logs=<workspace dir>]
//       [--report=<markdown file>]
//
// Seeds every fault of every provider in scratch copies of the repository, one
// copy for each worker, and appends one `proofs.jsonl` row per fault under
// `<logs>/logs`. With --report the markdown report is written from the rows
// this run logged. The working tree is not changed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claudart/io/file_io.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';

import 'closure_faults.dart';
import 'command_faults.dart';
import 'controls.dart';
import 'fault.dart';
import 'listener_faults.dart';
import 'report.dart';
import 'runner.dart';
import 'table_faults.dart';

const _providers = <FaultProvider>[
  TransitionTableFaults(),
  ClosureEvidenceFaults(),
  ClaudartCommandFaults(),
  HandoffListenerFaults(),
];

String? _option(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}

Future<void> _copyRepository(String from, String to) async {
  Directory(to).createSync(recursive: true);
  final copied = await Process.run('rsync', [
    '-a',
    '--exclude=.git',
    '--exclude=coverage',
    '--exclude=build',
    '--exclude=mutation-test-report',
    '$from/',
    '$to/',
  ]);
  if (copied.exitCode != 0) throw StateError('rsync failed: ${copied.stderr}');
  final pub = await Process.run('dart', ['pub', 'get', '--offline'], workingDirectory: to);
  if (pub.exitCode != 0) throw StateError('pub get failed in $to: ${pub.stderr}');
}

Future<void> main(List<String> args) async {
  final repository = Directory.current.path;
  final workers = int.parse(_option(args, 'workers') ?? '1');
  final limit = int.tryParse(_option(args, 'limit') ?? '');
  final only = _option(args, 'only');
  final proofName = _option(args, 'proof');
  final workspace = _option(args, 'logs') ?? '/tmp/claudart_proof_audit/ws';
  final reportPath = _option(args, 'report');
  final skipControls = args.contains('--skip-controls');
  final started = DateTime.now().toUtc();
  final proofsLog = File(logFilePath('$workspace/logs', LogFile.proofs));

  if (args.contains('--report-only')) {
    final rows = [
      for (final line in proofsLog.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ];
    File(reportPath!).writeAsStringSync(renderReport(rows));
    stdout.writeln('report: $reportPath, from ${rows.length} logged rows');
    return;
  }

  final logger = SessionLogger.plain(
    io: const RealFileIO(),
    workspacePath: workspace,
  );

  final work = <(FaultProvider, SeededFault)>[
    for (final provider in _providers)
      if (proofName == null || provider.proof == proofName)
        for (final fault in provider.faults(repository))
          if (only == null || fault.description.contains(only)) (provider, fault),
  ];
  final queue = limit == null ? work : work.take(limit).toList();
  stdout.writeln('${queue.length} faults, $workers worker(s), logging to '
      '${logFilePath('$workspace/logs', LogFile.proofs)}');

  var next = 0;
  var done = 0;
  final counts = {for (final verdict in ProofVerdict.values) verdict: 0};

  Future<void> worker(int number) async {
    final scratch = '/tmp/claudart_proof_audit/w$number';
    if (Directory(scratch).existsSync()) Directory(scratch).deleteSync(recursive: true);
    await _copyRepository(repository, scratch);
    final runner = AuditRunner(scratchRoot: scratch, logger: logger);
    if (number == 0 && !skipControls) {
      for (final control in controls) {
        final result = await runner.check(_providers.first, control.fault);
        stdout.writeln('control ${result.verdict.name} (expected '
            '${control.expected.name}): ${control.fault.description}');
        if (result.verdict != control.expected) {
          throw StateError('the audit cannot be trusted: '
              '${control.fault.description} came out ${result.verdict.name}');
        }
      }
    }
    while (next < queue.length) {
      final (provider, fault) = queue[next++];
      final result = await runner.check(provider, fault);
      counts[result.verdict] = counts[result.verdict]! + 1;
      done++;
      stdout.writeln('[$done/${queue.length}] ${result.verdict.name} '
          '(tier ${result.tier}, ${result.durationMs}ms) ${fault.description} '
          '${fault.sourceFile}:${fault.sourceLine}');
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker(i)]);
  stdout.writeln('done: ${counts.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}');

  if (reportPath != null) {
    final logged = File(logFilePath('$workspace/logs', LogFile.proofs))
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .where((row) => !DateTime.parse(row[LogEntryField.ts.name] as String).isBefore(started))
        .toList();
    File(reportPath).writeAsStringSync(renderReport(logged));
    stdout.writeln('report: $reportPath');
  }
}
