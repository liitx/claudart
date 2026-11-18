// test_trace.dart — a test says what it gave the code, expected and got
//
// A traced check records, for a check a test makes, the input it gave the code,
// the value it expected and the value it got, and the log rows the check
// caused. The expectation is taken before the code runs (the check is made
// first and verified after), so a test cannot choose its expectation from the
// answer without it showing. It writes only when `CLAUDART_TEST_TRACE` names a
// file, so an ordinary run is unchanged.
//
//   CLAUDART_TEST_TRACE=/tmp/trace.jsonl dart test <files>
//   make diagram TRACE=/tmp/trace.jsonl [HTML=<file>]
//
// Use:
//   final check = tracer.check(label: 'a status outside a project',
//       input: 'status', expected: 'failed', obligation: SpecObligation.record);
//   final actual = runTheCode();
//   check.verify(actual, caused: rowsTheRunWrote);

import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/trace_diagram.dart';
import 'package:test/test.dart';

import 'spec_obligations.dart';

/// The environment variable that names the file a trace is written to.
const String traceEnvVar = 'CLAUDART_TEST_TRACE';

/// Orders the expectations and the answers recorded in this process.
var _sequence = 0;

class TraceRecorder {
  TraceRecorder({this.path});

  /// The recorder tests use: writes to the file the environment names, if any.
  factory TraceRecorder.fromEnvironment() =>
      TraceRecorder(path: Platform.environment[traceEnvVar]);

  /// The file rows are appended to, or null for a recorder that writes nothing.
  final String? path;

  /// Starts a check: the expectation is recorded now, before the code runs.
  TracedCheck check({
    required String label,
    required Object? input,
    required Object? expected,
    SpecObligation? obligation,
  }) =>
      TracedCheck._(
        recorder: this,
        label: label,
        input: input,
        expected: expected,
        obligation: obligation,
        expectedAt: _sequence++,
      );

  void _write(TraceRow row) {
    final file = path;
    if (file == null) return;
    File(file).writeAsStringSync(
      '${jsonEncode(row.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

/// A check whose expectation is taken and whose answer is not yet known.
class TracedCheck {
  TracedCheck._({
    required this.recorder,
    required this.label,
    required this.input,
    required this.expected,
    required this.obligation,
    required this.expectedAt,
  });

  final TraceRecorder recorder;
  final String label;
  final Object? input;
  final Object? expected;
  final SpecObligation? obligation;
  final int expectedAt;

  /// Gives the answer: records the row, then fails the test if it does not
  /// match the expectation.
  void verify(Object? actual, {List<String> caused = const []}) {
    final matcher = wrapMatcher(expected);
    final passed = matcher.matches(actual, {});
    recorder._write(TraceRow(
      test: label,
      obligation: obligation?.name,
      input: '$input',
      expected: expected is Matcher
          ? (expected as Matcher).describe(StringDescription()).toString()
          : '$expected',
      actual: '$actual',
      passed: passed,
      expectedAt: expectedAt,
      actualAt: _sequence++,
      caused: caused,
    ));
    expect(actual, matcher);
  }
}

/// The recorder every test uses.
final TraceRecorder tracer = TraceRecorder.fromEnvironment();
