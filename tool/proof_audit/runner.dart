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
    required this.caughtBy,
    required this.durationMs,
  });

  final SeededFault fault;
  final ProofVerdict verdict;

  /// The checking tier that decided it: 1 the named proofs, 2 the wider suite.
  final int tier;
  final List<String> caughtBy;
  final int durationMs;
}

/// What a `dart test -r json` run said.
class TestJudgement {
  const TestJudgement({required this.failed, required this.invalid});

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
  final failed = <String>[];
  var invalid = false;
  for (final line in const LineSplitter().convert(reporterLines)) {
    if (!line.startsWith('{')) continue;
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    final test = event['test'];
    if (event['type'] == 'testStart' && test is Map<String, dynamic>) {
      names[test['id'] as int] = test['name'] as String;
    } else if (event['type'] == 'testDone') {
      final result = event['result'];
      if (result != 'failure' && result != 'error') continue;
      final name = names[event['testID'] as int] ?? 'unnamed test';
      if (name.startsWith('loading ')) {
        invalid = true;
      } else {
        failed.add(name);
      }
    }
  }
  if (exitCode != 0 && failed.isEmpty) invalid = true;
  return TestJudgement(failed: failed, invalid: invalid);
}

class AuditRunner {
  AuditRunner({required this.scratchRoot, required this.logger});

  /// A scratch copy of the repository, owned by this runner alone.
  final String scratchRoot;
  final SessionLogger logger;

  static const _testTimeout = Duration(minutes: 6);

  Future<FaultResult> check(FaultProvider provider, SeededFault fault) async {
    final clock = Stopwatch()..start();
    final path = '$scratchRoot/${fault.sourceFile}';
    final original = File(path).readAsStringSync();
    try {
      File(path).writeAsStringSync(fault.apply(original));
      var tier = 1;
      var judgement = await _run(provider.tierOneTests);
      if (!judgement.invalid && judgement.failed.isEmpty) {
        tier = 2;
        judgement = await _run(provider.tierTwoTests);
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
        caughtBy: judgement.failed,
        durationMs: clock.elapsedMilliseconds,
      );
      logger.logProofFault(
        proof: fault.proof,
        fault: fault.description,
        sourceFile: fault.sourceFile,
        sourceLine: fault.sourceLine,
        verdict: verdict,
        tier: tier,
        caughtBy: judgement.failed,
        durationMs: result.durationMs,
      );
      return result;
    } finally {
      File(path).writeAsStringSync(original);
    }
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
    final exitCode = await process.exitCode.timeout(
      _testTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await reading;
    return judgeTestRun(output.toString(), exitCode);
  }
}
