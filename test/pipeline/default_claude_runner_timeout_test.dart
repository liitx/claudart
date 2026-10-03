@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:claudart/config.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/debug_mode.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The per-step timeout, driven against a FAKE `claude` executable (a shell
/// script), so the real process-tree kill is exercised, not simulated.
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('claude_timeout_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const resultLine = '{"type":"result","result":"all good","stop_reason":"end_turn",'
      '"duration_ms":5,"num_turns":1,"total_cost_usd":0.0,'
      '"usage":{"input_tokens":1,"output_tokens":1,'
      '"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}';

  /// Writes an executable fake `claude` and returns its path.
  String fakeClaude(String body) {
    final script = File(p.join(tmp.path, 'claude'))..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  Future<StepResult?> run(String executable, {Duration? timeout, StepDebugTrace? trace}) =>
      defaultClaudeRunner(
        model: AgentModel.haiku,
        systemPrompt: 'system',
        message: 'hello',
        workingDir: tmp.path,
        timeout: timeout,
        executable: executable,
        traceOverride: trace,
      );

  bool alive(String pidFile) {
    final pid = File(pidFile).readAsStringSync().trim();
    return Process.runSync('kill', ['-0', pid]).exitCode == 0;
  }

  Future<void> waitUntilGone(List<String> pidFiles) async {
    for (var i = 0; i < 40; i++) {
      if (pidFiles.every((f) => !alive(f))) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  group('a step that never returns', () {
    const hangBody = 'echo \$\$ > "PIDS/parent"\n'
        'sleep 300 &\n'
        'echo \$! > "PIDS/child"\n'
        'wait';

    test('fails at the limit with a plain Exception that names the config key', () async {
      final pids = Directory(p.join(tmp.path, 'pids'))..createSync();
      final exe = fakeClaude(hangBody.replaceAll('PIDS', pids.path));
      final watch = Stopwatch()..start();

      Object? error;
      try {
        await run(exe, timeout: const Duration(seconds: 1));
      } on Object catch (e) {
        error = e;
      }

      expect(error, isA<Exception>());
      expect(error, isNot(isA<TimeoutException>()), reason: 'same Exception type as the non-zero-exit branch');
      expect('$error', contains('timed out after 1 second'));
      expect('$error', contains('stepTimeoutMinutes'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    });

    test('kills the WHOLE process tree: no orphaned grandchild survives', () async {
      final pids = Directory(p.join(tmp.path, 'pids'))..createSync();
      final exe = fakeClaude(hangBody.replaceAll('PIDS', pids.path));

      await expectLater(run(exe, timeout: const Duration(seconds: 1)), throwsException);
      final files = [p.join(pids.path, 'parent'), p.join(pids.path, 'child')];
      await waitUntilGone(files);

      expect(alive(files[0]), isFalse, reason: 'the direct child must be gone');
      expect(alive(files[1]), isFalse, reason: 'the grandchild must be gone too (it used to be orphaned)');
    });

    test('the debug trace still records the step and the timeout as the exit condition', () async {
      final pids = Directory(p.join(tmp.path, 'pids'))..createSync();
      final exe = fakeClaude(hangBody.replaceAll('PIDS', pids.path));
      final log = StringBuffer();

      await expectLater(
        run(exe, timeout: const Duration(seconds: 1), trace: StepDebugTrace.forTesting(log.write)),
        throwsException,
      );

      final text = log.toString();
      expect(text, contains(kTraceLabelStep), reason: 'the step header is still written');
      expect(text, contains(kTraceLabelExit), reason: 'the exit record is still written');
      expect(text, contains('TIMED OUT'), reason: 'and it says why');
      expect(text, contains(kTraceLabelException), reason: 'the failure is traced like any other');
    });
  });

  group('a step that finishes', () {
    test('inside the limit is unaffected', () async {
      final exe = fakeClaude("printf '%s\\n' '$resultLine'");
      final result = await run(exe, timeout: const Duration(seconds: 30));
      expect(result?.text, 'all good');
    });

    test('with no limit (null) can take as long as it needs', () async {
      final exe = fakeClaude("sleep 2\nprintf '%s\\n' '$resultLine'");
      final result = await run(exe, timeout: null);
      expect(result?.text, 'all good');
    });

    test('a slow step within a longer limit is not cut short', () async {
      final exe = fakeClaude("sleep 2\nprintf '%s\\n' '$resultLine'");
      final result = await run(exe, timeout: const Duration(seconds: 20));
      expect(result?.text, 'all good');
    });
  });

  test('a non-zero exit still throws the same kind of Exception as before', () async {
    final exe = fakeClaude('echo boom 1>&2\nexit 3');
    Object? error;
    try {
      await run(exe, timeout: const Duration(seconds: 30));
    } on Object catch (e) {
      error = e;
    }
    expect(error, isA<Exception>());
    expect('$error', contains('claude exited 3'));
    expect('$error', isNot(contains('timed out')));
  });

  test('the default limit is 15 minutes', () {
    expect(defaultStepTimeout, const Duration(minutes: 15));
  });
}
