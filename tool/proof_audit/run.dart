// run.dart — audits the proofs against seeded faults and logs what it finds
//
//   dart run tool/proof_audit/run.dart [--workers=N] [--limit=N] [--only=text]
//       [--proof=name] [--root=<repo>] [--mutants=<lib file or dir>]
//       [--mirror-only] [--learned=<file>] [--faults-from=<file of file|description>] [--scratch=<dir>] [--changed-since=<git ref>] [--ledger=<markdown file>]
//       [--equivalents=<registry>] [--fail-on-survivors] [--run-timeout=<seconds>] [--skip-controls]
//       [--report-only]
//       [--logs=<workspace dir>]
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

import 'changed_lines.dart';
import 'controls.dart';
import 'ledger.dart';
import 'fault.dart';
import 'mirror.dart';
import 'overrides.dart';
import 'mutant_faults.dart';
import 'providers.dart';
import 'report.dart';
import 'runner.dart';

String? _option(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}

/// The lines of `lib/` that differ from [ref] (committed or not), and every line
/// of a file git does not track yet.
Future<Map<String, List<LineRange>>> _changedSince(String root, String ref) async {
  final diff = await Process.run('git', ['diff', '-U0', ref, '--', 'lib'], workingDirectory: root);
  if (diff.exitCode != 0) throw StateError('git diff failed: ${diff.stderr}');
  final changed = parseChangedLines(diff.stdout as String);
  final untracked = await Process.run(
    'git',
    ['ls-files', '--others', '--exclude-standard', '--', 'lib'],
    workingDirectory: root,
  );
  for (final path in (untracked.stdout as String).split('\n').where((p) => p.endsWith('.dart'))) {
    final length = File('$root/$path').readAsLinesSync().length;
    changed[path] = [(first: 1, last: length)];
  }
  return changed;
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
  final overrides = File('$to/pubspec_overrides.yaml');
  if (overrides.existsSync()) {
    overrides.writeAsStringSync(
      absolutizeOverridePaths(overrides.readAsStringSync(), from),
    );
  }
  final pub = await Process.run('dart', ['pub', 'get', '--offline'], workingDirectory: to);
  if (pub.exitCode != 0) throw StateError('pub get failed in $to: ${pub.stderr}');
}

Future<void> main(List<String> args) async {
  final repository = Directory(_option(args, 'root') ?? Directory.current.path).absolute.path;
  final mutantsPath = _option(args, 'mutants');
  final runTimeout = Duration(seconds: int.parse(_option(args, 'run-timeout') ?? '360'));
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

  // A mutants run seeds one-line mutants of the named files, each checked by
  // the file's mirrored test and then by the whole test directory; otherwise the
  // matrices of providers.dart are seeded.
  final mirrorOnly = args.contains('--mirror-only');
  // Only the faults a file names, one `file|description` per line: a rerun of
  // chosen mutants, for instance survivors of a mirror-only run against the
  // whole suite.
  final chosen = _option(args, 'faults-from') == null
      ? null
      : File(_option(args, 'faults-from')!).readAsLinesSync().where((l) => l.trim().isNotEmpty).toSet();
  // Each run's working copies live under their own directory, so two runs never
  // delete each other's.
  final scratchBase = _option(args, 'scratch') ?? '/tmp/claudart_proof_audit';
  final changedRef = _option(args, 'changed-since');
  final changed =
      changedRef == null ? null : await _changedSince(repository, changedRef);
  final providers = mutantsPath == null
      ? auditProviders
      : <FaultProvider>[
          for (final file in sourceFilesUnder(repository, mutantsPath))
            if ((changed == null || changed.containsKey(file)) &&
                (!mirrorOnly || homeTest(repository, file) != null))
              FileMutantFaults(
                file: file,
                tierOne: [
                  if (homeTest(repository, file) case final home?) home.path,
                ],
                tierTwo: mirrorOnly ? const [] : const ['test'],
              ),
        ];
  final controlFile = mutantsPath == null
      ? defaultControlFile
      : (sourceFilesUnder(repository, mutantsPath)
          .where((file) =>
              (changed == null || changed.containsKey(file)) &&
              (!mirrorOnly || homeTest(repository, file) != null))
          .firstOrNull ??
          defaultControlFile);
  // The controls always check against the wider suite, so a test that reacts to
  // any edit is learned even in a mirror-only run.
  // A change gate runs on every commit, so its controls stop at tier one: the
  // source-reading tests learned by earlier full runs are read from a file.
  final controlProvider = mutantsPath == null
      ? providers.first
      : FileMutantFaults(
          file: controlFile,
          tierOne: [
            if (homeTest(repository, controlFile) case final home?) home.path,
          ],
          tierTwo: changed != null ? const [] : const ['test'],
        );
  final work = <(FaultProvider, SeededFault)>[
    for (final provider in providers)
      if (proofName == null || provider.proof == proofName)
        for (final fault in provider.faults(repository))
          if ((only == null || fault.description.contains(only)) &&
              (chosen == null || chosen.contains('${fault.sourceFile}|${fault.description}')) &&
              (changed == null ||
                  isChanged(changed[fault.sourceFile] ?? const [], fault.sourceLine)))
            (provider, fault),
  ];
  final queue = limit == null ? work : work.take(limit).toList();
  stdout.writeln('${queue.length} faults, $workers worker(s), logging to '
      '${logFilePath('$workspace/logs', LogFile.proofs)}');

  // Test files a change that alters no behavior makes fail: they read source
  // text, so a wider run leaves them out. Learned by the controls below.
  final learnedPath = _option(args, 'learned') ?? 'tool/proof_audit/source_sensitive_tests.txt';
  final learned = <String>[
    if (File(learnedPath).existsSync())
      for (final line in File(learnedPath).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
  ];

  if (!skipControls) {
    final controlScratch = '$scratchBase/control';
    if (Directory(controlScratch).existsSync()) Directory(controlScratch).deleteSync(recursive: true);
    await _copyRepository(repository, controlScratch);
    final runner = AuditRunner(
      scratchRoot: controlScratch,
      logger: logger,
      testTimeout: runTimeout,
      learnedExclusions: learned,
    );
    for (final control in controlsFor(controlFile)) {
      var result = await runner.check(controlProvider, control.fault);
      if (result.verdict != control.expected &&
          control.expected == ProofVerdict.missed &&
          result.verdict == ProofVerdict.caught &&
          result.failedFiles.isNotEmpty) {
        learned.addAll(result.failedFiles);
        File(learnedPath).writeAsStringSync(
          '# Test files that fail on a change that alters no behavior: they read\n'
          '# source text, so a wider run leaves them out. Learned by the controls.\n'
          '${(learned.toSet().toList()..sort()).join('\n')}\n',
        );
        stdout.writeln('learned: ${result.failedFiles.join(', ')} fail on a change '
            'that alters no behavior, so wider runs leave them out');
        result = await runner.check(controlProvider, control.fault);
      }
      stdout.writeln('control ${result.verdict.name} (expected '
          '${control.expected.name}): ${control.fault.description}');
      if (result.verdict != control.expected) {
        throw StateError('the audit cannot be trusted: '
            '${control.fault.description} came out ${result.verdict.name}');
      }
    }
  }

  var next = 0;
  var done = 0;
  final counts = {for (final verdict in ProofVerdict.values) verdict: 0};

  Future<void> worker(int number) async {
    final scratch = '$scratchBase/w$number';
    if (Directory(scratch).existsSync()) Directory(scratch).deleteSync(recursive: true);
    await _copyRepository(repository, scratch);
    final runner = AuditRunner(
      scratchRoot: scratch,
      logger: logger,
      testTimeout: runTimeout,
      learnedExclusions: learned,
    );
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

  final ledgerPath = _option(args, 'ledger');
  final equivalentsPath = _option(args, 'equivalents') ?? 'tool/proof_audit/accepted_equivalents.txt';
  final equivalents = File(equivalentsPath).existsSync()
      ? parseEquivalents(File(equivalentsPath).readAsStringSync())
      : <String, String>{};
  final thisRun = mutantRows([
    for (final line in proofsLog.readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ].where((row) => !DateTime.parse(row[LogEntryField.ts.name] as String).isBefore(started)).toList());
  final survivors = unacceptedSurvivors(thisRun, equivalents).length;
  if (ledgerPath != null) {
    final rows = mutantRows([
      for (final line in proofsLog.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ].where((row) => !DateTime.parse(row[LogEntryField.ts.name] as String).isBefore(started)).toList());
    File(ledgerPath).writeAsStringSync(renderLedger(
      rows: rows,
      sources: {
        for (final file in {for (final row in rows) row.file})
          file: File('$repository/$file').readAsStringSync(),
      },
      lcov: const {},
      excludedTests: learned,
      equivalents: equivalents,
      root: repository,
      title: 'Lines changed since ${changedRef ?? 'the start'}: which test guards them',
    ));
    stdout.writeln('ledger: $ledgerPath');
  }

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

  if (args.contains('--fail-on-survivors') && survivors > 0) {
    stdout.writeln('$survivors mutant(s) survived: no test fails when those lines are '
        'wrong. The ledger names the existing tests each belongs with.');
    exit(1);
  }
}
