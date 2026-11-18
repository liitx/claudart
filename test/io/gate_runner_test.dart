// The one way a gate command is run (gaps R15 and the runner consolidation): a
// shell command, its exit code and the tail of what it wrote, so the data to
// judge a gate is not lost.

import 'dart:io';

import 'package:claudart/io/gate_runner.dart';
import 'package:claudart/io/process_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

ProcessResult _result(int exitCode, {String out = '', String err = ''}) =>
    ProcessResult(1, exitCode, out, err);

void main() {
  late MockProcessRunner runner;

  setUp(() {
    runner = MockProcessRunner();
    registerFallbackValue(<String>[]);
  });

  group('the shell invocation', () {
    test('runGate passes the whole command to the shell as one argument, in '
        'the working directory', () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => _result(0));
      await runGate(runner, 'make a && make b', '/project');
      verify(() => runner.run(
            shellExecutable,
            [shellCommandFlag, 'make a && make b'],
            workingDirectory: '/project',
          )).called(1);
    });

    test('runGateSync passes the same invocation', () {
      when(() => runner.runSync(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(_result(0));
      runGateSync(runner, 'make a && make b', '/project');
      verify(() => runner.runSync(
            shellExecutable,
            [shellCommandFlag, 'make a && make b'],
            workingDirectory: '/project',
          )).called(1);
    });
  });

  group('the result', () {
    test('passes only on exit code 0', () {
      expect(const GateResult(exitCode: 0, outputTail: '', durationMs: 1).passed,
          isTrue);
      expect(const GateResult(exitCode: 1, outputTail: '', durationMs: 1).passed,
          isFalse);
      expect(const GateResult(exitCode: 127, outputTail: '', durationMs: 1).passed,
          isFalse);
    });

    test('carries the exit code', () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => _result(2, err: 'boom'));
      final result = await runGate(runner, 'x', '/p');
      expect(result.exitCode, 2);
      expect(result.passed, isFalse);
    });

    test('carries what the command wrote, standard output then standard error',
        () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => _result(1, out: 'built a\n', err: 'failed b\n'));
      final result = await runGate(runner, 'x', '/p');
      expect(result.outputTail, 'built a\nfailed b');
    });

    test('keeps only the last lines of a long output', () async {
      final many = [for (var i = 1; i <= 100; i++) 'line $i'].join('\n');
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => _result(1, out: many));
      final lines = (await runGate(runner, 'x', '/p')).outputTail.split('\n');
      expect(lines, hasLength(gateOutputTailLines));
      expect(lines.last, 'line 100');
      expect(lines.first, 'line ${100 - gateOutputTailLines + 1}');
    });

    test('keeps output that is not text as its description', () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => ProcessResult(1, 1, <int>[1, 2], null));
      final result = await runGate(runner, 'x', '/p');
      expect(result.outputTail, isA<String>());
    });

    test('measures how long it ran by the clock it is given', () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => _result(0));
      final times = [
        DateTime.utc(2026, 1, 1, 12),
        DateTime.utc(2026, 1, 1, 12, 0, 0, 250),
      ];
      final result = await runGate(
        runner,
        'x',
        '/p',
        clock: () => times.removeAt(0),
      );
      expect(result.durationMs, 250);
    });

    test('measures the synchronous runner by the same clock', () {
      when(() => runner.runSync(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(_result(0));
      final times = [
        DateTime.utc(2026, 1, 1, 12),
        DateTime.utc(2026, 1, 1, 12, 0, 3),
      ];
      final result = runGateSync(runner, 'x', '/p', clock: () => times.removeAt(0));
      expect(result.durationMs, 3000);
    });

    test('measures a gate that cannot start too', () {
      when(() => runner.runSync(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenThrow(const ProcessException('sh', ['-c', 'x'], 'not found'));
      final times = [
        DateTime.utc(2026, 1, 1, 12),
        DateTime.utc(2026, 1, 1, 12, 0, 0, 7),
      ];
      final result = runGateSync(runner, 'x', '/p', clock: () => times.removeAt(0));
      expect(result.durationMs, 7);
    });
  });

  group('a gate that cannot start', () {
    test('is a failure with the reason, not an exception', () async {
      when(() => runner.run(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenThrow(const ProcessException('sh', ['-c', 'x'], 'not found'));
      final result = await runGate(runner, 'x', '/p');
      expect(result.passed, isFalse);
      expect(result.outputTail, contains('not found'));
    });

    test('is the same for the synchronous runner', () {
      when(() => runner.runSync(any(), any(),
              workingDirectory: any(named: 'workingDirectory')))
          .thenThrow(const ProcessException('sh', ['-c', 'x'], 'not found'));
      final result = runGateSync(runner, 'x', '/p');
      expect(result.passed, isFalse);
      expect(result.outputTail, contains('not found'));
    });
  });
}
