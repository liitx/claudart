import 'dart:convert';
import 'dart:io';

import 'package:claudart/logging/trace_diagram.dart';
import 'package:test/test.dart';

import '../helpers/spec_obligations.dart';
import 'test_trace.dart';

void main() {
  late Directory directory;
  late File trace;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('test_trace_');
    trace = File('${directory.path}/trace.jsonl');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  List<TraceRow> rows() =>
      trace.existsSync() ? traceRowsOfJsonl(trace.readAsStringSync()) : [];

  group('a recorder with no file', () {
    test('records nothing and still checks', () {
      final recorder = TraceRecorder();
      recorder.check(label: 'a', input: 1, expected: 2).verify(2);
      expect(trace.existsSync(), isFalse);
    });

    test('still fails a check that does not match', () {
      expect(
        () => TraceRecorder().check(label: 'a', input: 1, expected: 2).verify(3),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('a recorder with a file', () {
    test('writes one row for a check, with what the test gave and expected '
        'and what it got', () {
      TraceRecorder(path: trace.path)
          .check(label: 'adds', input: 'one plus one', expected: 2)
          .verify(2);
      final row = rows().single;
      expect(row.test, 'adds');
      expect(row.input, 'one plus one');
      expect(row.expected, '2');
      expect(row.actual, '2');
      expect(row.passed, isTrue);
    });

    test('records the expectation before the answer', () {
      final recorder = TraceRecorder(path: trace.path);
      final check = recorder.check(label: 'a', input: 1, expected: 2);
      check.verify(2);
      expect(rows().single.expectedFirst, isTrue);
    });

    test('records a mismatch, then fails the test', () {
      final recorder = TraceRecorder(path: trace.path);
      expect(
        () => recorder.check(label: 'a', input: 1, expected: 2).verify(3),
        throwsA(isA<TestFailure>()),
      );
      final row = rows().single;
      expect(row.passed, isFalse);
      expect(row.expected, '2');
      expect(row.actual, '3');
    });

    test('describes a matcher as the expectation', () {
      TraceRecorder(path: trace.path)
          .check(label: 'a', input: 1, expected: greaterThan(1))
          .verify(5);
      expect(rows().single.expected, contains('greater than'));
      expect(rows().single.passed, isTrue);
    });

    test('names the obligation a check belongs to, or none', () {
      final recorder = TraceRecorder(path: trace.path);
      recorder
          .check(
              label: 'a',
              input: 1,
              expected: 1,
              obligation: SpecObligation.record)
          .verify(1);
      recorder.check(label: 'b', input: 1, expected: 1).verify(1);
      expect(rows().map((row) => row.obligation), ['record', null]);
      expect(rows().last.anchor, unanchoredObligation);
    });

    test('records the log rows a check caused', () {
      TraceRecorder(path: trace.path)
          .check(label: 'a', input: 1, expected: 1)
          .verify(1, caused: ['interactions: status ok']);
      expect(rows().single.caused, ['interactions: status ok']);
    });

    test('appends: a second check does not replace the first', () {
      final recorder = TraceRecorder(path: trace.path);
      recorder.check(label: 'a', input: 1, expected: 1).verify(1);
      recorder.check(label: 'b', input: 1, expected: 1).verify(1);
      expect(rows().map((row) => row.test), ['a', 'b']);
    });

    test('writes one JSON object to each line', () {
      TraceRecorder(path: trace.path)
          .check(label: 'a', input: 'x\ny', expected: 1)
          .verify(1);
      expect(trace.readAsLinesSync(), hasLength(1));
      expect(jsonDecode(trace.readAsLinesSync().single), isA<Map<String, dynamic>>());
    });

    test('a check that is never verified writes nothing', () {
      TraceRecorder(path: trace.path).check(label: 'a', input: 1, expected: 1);
      expect(trace.existsSync(), isFalse);
    });
  });
}
