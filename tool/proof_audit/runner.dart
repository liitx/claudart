// runner.dart — seeds one fault in a scratch copy and says whether the tests saw it
//
// The working tree is never touched: each worker owns a scratch copy of the
// repository, writes the faulty source into it, runs the tests there, and puts
// the original back. A fault is `caught` when a test fails, `missed` when
// every test passes, and `invalid` when the faulty source did not compile or
// the tests did not load, which shows nothing either way. A fault tier one
// missed is run again against the wider set, so the report can say whether a
// proof is weak (tier two caught it) or nothing in the suite sees it (missed).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/logger.dart';

import 'fault.dart';

/// How one fault ended.
class FaultResult {
  const FaultResult({
    required this.fault,
    required this.verdict,
    required this.tier,
    required this.attempts,
    required this.caughtBy,
    required this.failedFiles,
    required this.durationMs,
  });

  final SeededFault fault;
  final ProofVerdict verdict;

  /// The checking tier that decided it: 1 the named proofs, 2 the wider suite.
  final int tier;

  /// How many times the deciding tier's tests were run: 2 when the first run
  /// showed nothing (it did not load, or failed with no test to explain it) and
  /// was repeated, since three workers compiling at once can do that.
  final int attempts;
  final List<String> caughtBy;

  /// The test files with a failing test, for the exclusions the controls learn.
  final List<String> failedFiles;
  final int durationMs;
}

/// What a `dart test -r json` run said.
class TestJudgement {
  const TestJudgement({
    required this.failed,
    required this.invalid,
    this.timedOut = false,
    this.failedFiles = const [],
  });

  /// The test files that had a failing test.
  final List<String> failedFiles;

  /// The run was killed at its time limit: a repeat would only wait as long
  /// again, so it is not repeated.
  final bool timedOut;

  /// Titles of the tests that failed.
  final List<String> failed;

  /// The tests did not load or the run ended with no failure to explain it.
  final bool invalid;
}

/// Reads the JSON reporter's lines. A suite that cannot load is a failed test
/// named `loading <file>`; that, or a non-zero exit nothing explains, is
/// [TestJudgement.invalid], never a catch.
TestJudgement judgeTestRun(String reporterLines, int exitCode) {
  final names = <int, String>{};
  final errors = <int, String>{};
  final suitePaths = <int, String>{};
  final testSuite = <int, int>{};
  final failedFiles = <String>{};
  final failed = <String>[];
  var invalid = false;
  for (final line in const LineSplitter().convert(reporterLines)) {
    final event = _eventIn(line);
    if (event == null) continue;
    final test = event['test'];
    final suite = event['suite'];
    if (event['type'] == 'suite' && suite is Map<String, dynamic>) {
      suitePaths[suite['id'] as int] = suite['path'] as String;
    } else if (event['type'] == 'testStart' && test is Map<String, dynamic>) {
      names[test['id'] as int] = test['name'] as String;
      if (test['suiteID'] is int) testSuite[test['id'] as int] = test['suiteID'] as int;
    } else if (event['type'] == 'error') {
      errors[event['testID'] as int] =
          '${errors[event['testID'] as int] ?? ''}${event['error']}';
    } else if (event['type'] == 'testDone') {
      final result = event['result'];
      if (result != 'failure' && result != 'error') continue;
      final id = event['testID'] as int;
      final name = names[id] ?? noRecordedStartName;
      if (!name.startsWith('loading ')) {
        failed.add(name);
        final path = suitePaths[testSuite[id]];
        if (path != null) failedFiles.add(path);
      } else if (errors[id] == null || _failedToCompile(errors[id]!)) {
        // No error text, or text that says the source did not compile: nothing
        // was shown about the tests.
        invalid = true;
      } else {
        // The file compiled and then threw while loading (a group body ran the
        // changed code): the file breaks on the change, so it caught it.
        failed.add('${name.substring('loading '.length)} fails while loading');
        failedFiles.add(name.substring('loading '.length));
      }
    }
  }
  if (exitCode != 0 && failed.isEmpty) invalid = true;
  return TestJudgement(
    failed: failed,
    invalid: invalid,
    failedFiles: failedFiles.toList()..sort(),
  );
}

/// Whether a suite's load error says the source did not compile.
bool _failedToCompile(String error) =>
    error.contains('Compilation failed') ||
    RegExp(r'\.dart:\d+:\d+: Error:').hasMatch(error);

/// What a failure is called when its start was never read.
const noRecordedStartName = 'a test whose start was not recorded';

/// The reporter event on [line]. Commands under test write spinners and status
/// text straight to standard output, so raw text can come before an event on
/// its line, or after it; the event is the JSON object that starts at a `{"`
/// and closes at its matching brace.
Map<String, dynamic>? _eventIn(String line) {
  for (var at = line.indexOf('{"'); at >= 0; at = line.indexOf('{"', at + 1)) {
    final end = _closingBrace(line, at);
    if (end == null) continue;
    try {
      final decoded = jsonDecode(line.substring(at, end + 1));
      if (decoded is Map<String, dynamic> && decoded['type'] is String) {
        return decoded;
      }
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// The index of the brace that closes the object opened at [start], skipping
/// braces inside strings, or null when the line ends first.
int? _closingBrace(String line, int start) {
  var depth = 0;
  var inString = false;
  for (var i = start; i < line.length; i++) {
    final char = line[i];
    if (inString) {
      if (char == '\\') {
        i++;
      } else if (char == '"') {
        inString = false;
      }
    } else if (char == '"') {
      inString = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// The test files [tests] name under [root]: a directory is every `_test.dart`
/// file in it, a file stands for itself, and [excluded] files are left out.
/// Paths stay relative to [root], sorted, each once.
List<String> expandTests(String root, List<String> tests, List<String> excluded) {
  final files = <String>{};
  for (final test in tests) {
    final directory = Directory('$root/$test');
    if (directory.existsSync()) {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('_test.dart')) {
          files.add(entity.path.substring(root.length + 1));
        }
      }
    } else {
      files.add(test);
    }
  }
  return (files..removeAll(excluded)).toList()..sort();
}

class AuditRunner {
  AuditRunner({
    required this.scratchRoot,
    required this.logger,
    Future<TestJudgement> Function(List<String> tests)? runTests,
    this.testTimeout = const Duration(minutes: 6),
    List<String>? learnedExclusions,
  })  : _runTests = runTests,
        learnedExclusions = learnedExclusions ?? [];

  /// Test files left out of every wider run because a change that alters no
  /// behavior made them fail: they read source text, so they are not proofs of
  /// anything the program does. Learned from the controls, shared by workers.
  final List<String> learnedExclusions;

  /// How long one test run may take before it is killed.
  final Duration testTimeout;

  final Future<TestJudgement> Function(List<String> tests)? _runTests;

  /// A scratch copy of the repository, owned by this runner alone.
  final String scratchRoot;
  final SessionLogger logger;

  Future<FaultResult> check(FaultProvider provider, SeededFault fault) async {
    final clock = Stopwatch()..start();
    final path = '$scratchRoot/${fault.sourceFile}';
    final original = File(path).readAsStringSync();
    try {
      File(path).writeAsStringSync(fault.apply(original));
      // With no tier-one tests (a file nothing mirrors) there is nothing to run
      // first: `dart test` with no paths would run everything as tier one.
      var tier = provider.tierOneTests.isEmpty ? 2 : 1;
      var (judgement, attempts) = tier == 1
          ? await _runOnceMoreIfInvalid(provider.tierOneTests)
          : (const TestJudgement(failed: [], invalid: false), 0);
      if (tier == 2 || (!judgement.invalid && judgement.failed.isEmpty)) {
        tier = 2;
        (judgement, attempts) = await _runOnceMoreIfInvalid(
          expandTests(
            scratchRoot,
            provider.tierTwoTests,
            [...provider.excludedTests, ...learnedExclusions],
          ),
        );
      }
      final verdict = judgement.invalid
          ? ProofVerdict.invalid
          : judgement.failed.isEmpty
              ? ProofVerdict.missed
              : ProofVerdict.caught;
      final result = FaultResult(
        fault: fault,
        verdict: verdict,
        tier: tier,
        attempts: attempts,
        caughtBy: judgement.failed,
        failedFiles: judgement.failedFiles,
        durationMs: clock.elapsedMilliseconds,
      );
      logger.logProofFault(
        proof: fault.proof,
        fault: fault.description,
        sourceFile: fault.sourceFile,
        sourceLine: fault.sourceLine,
        verdict: verdict,
        tier: tier,
        attempts: attempts,
        caughtBy: judgement.failed,
        durationMs: result.durationMs,
      );
      return result;
    } finally {
      File(path).writeAsStringSync(original);
    }
  }

  /// The run, and the judgement of a second run if the first showed nothing.
  Future<(TestJudgement, int)> _runOnceMoreIfInvalid(List<String> tests) async {
    final first = await (_runTests ?? _run)(tests);
    if (!first.invalid || first.timedOut) return (first, 1);
    return (await (_runTests ?? _run)(tests), 2);
  }

  Future<TestJudgement> _run(List<String> tests) async {
    final process = await Process.start(
      'dart',
      ['test', '-r', 'json', '--timeout', '4x', ...tests],
      workingDirectory: scratchRoot,
    );
    final output = StringBuffer();
    final reading = process.stdout.transform(utf8.decoder).forEach(output.write);
    process.stderr.drain<void>();
    process.stdin.close().ignore();
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      testTimeout,
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await reading;
    final judged = judgeTestRun(output.toString(), exitCode);
    return timedOut
        ? TestJudgement(
            failed: judged.failed,
            invalid: true,
            timedOut: true,
            failedFiles: judged.failedFiles,
          )
        : judged;
  }
}
