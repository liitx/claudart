// debug_mode_test.dart — runtime flag × env var matrix.
//
// Both sources must OR together. Tests inject the env map directly so
// they never depend on the host environment.

import 'package:claudart/pipeline/debug_mode.dart';
import 'package:test/test.dart';

void main() {
  // Tests reset the runtime flag between cases — it's a process-level
  // global mutated by the CLI, and leaking state between tests would
  // mask bugs.
  tearDown(() {
    setDebugEnabled(false);
    suppressAmbientDebug(false);
  });

  // ── exported constants ────────────────────────────────────────────────────

  group('exported constants', () {
    test('CLAUDART_DEBUG is the env var name', () {
      expect(kClaudartDebugEnvVar, equals('CLAUDART_DEBUG'));
    });

    test('CLAUDART_DEBUG_PATH is the path-override env var name', () {
      expect(kClaudartDebugPathEnvVar, equals('CLAUDART_DEBUG_PATH'));
    });

    test('enabled value is "1"', () {
      expect(kClaudartDebugEnabledValue, equals('1'));
    });

    test('default log path is non-empty + .log-suffixed', () {
      expect(kDefaultClaudartDebugLogPath, isNotEmpty);
      expect(kDefaultClaudartDebugLogPath, endsWith('.log'));
    });
  });

  // ── debugEnabled matrix: (runtime × env) → expected ─────────────────────

  group('debugEnabled — runtime × env matrix', () {
    final cases = <(bool runtime, String? envValue, bool expected)>[
      (false, null,                            false), // both off
      (false, '0',                             false), // env set but not "1"
      (false, '',                              false), // env empty
      (false, 'true',                          false), // env truthy-looking but not "1"
      (true,  null,                            true),  // runtime only
      (false, kClaudartDebugEnabledValue,      true),  // env only
      (true,  kClaudartDebugEnabledValue,      true),  // both on
      (true,  '0',                             true),  // runtime overrides env=0
    ];

    for (final (runtime, envValue, expected) in cases) {
      test('runtime=$runtime  env="${envValue ?? '<unset>'}" → $expected', () {
        setDebugEnabled(runtime);
        final env = envValue == null
            ? <String, String>{}
            : {kClaudartDebugEnvVar: envValue};
        expect(debugEnabled(environment: env), equals(expected));
      });
    }
  });

  // ── a sensitive project suppresses the ambient env var, not the flag ─────

  group('debugEnabled — suppressed for a sensitive project', () {
    final cases = <(bool runtime, String? envValue, bool expected)>[
      (false, null,                       false), // nothing asked
      (false, kClaudartDebugEnabledValue, false), // ambient env: ignored
      (true,  null,                       true),  // explicit flag: still works
      (true,  kClaudartDebugEnabledValue, true),  // flag wins over suppression
    ];

    for (final (runtime, envValue, expected) in cases) {
      test('runtime=$runtime  env="${envValue ?? '<unset>'}" → $expected', () {
        setDebugEnabled(runtime);
        suppressAmbientDebug(true);
        final env = envValue == null
            ? <String, String>{}
            : {kClaudartDebugEnvVar: envValue};
        expect(debugEnabled(environment: env), equals(expected));
      });
    }

    test('lifting the suppression restores the env var', () {
      suppressAmbientDebug(true);
      suppressAmbientDebug(false);
      expect(
        debugEnabled(environment: {kClaudartDebugEnvVar: '1'}),
        isTrue,
      );
    });

    test('the log file follows the same decision', () {
      suppressAmbientDebug(true);
      expect(
        debugLogFile(environment: {kClaudartDebugEnvVar: '1'}),
        isNull,
      );
    });

    test('the notice names the cause and the way around it', () {
      expect(kAmbientDebugSuppressedNotice, contains('sensitive'));
      expect(kAmbientDebugSuppressedNotice, contains('--debug'));
    });
  });

  // ── debugLogFile path resolution ─────────────────────────────────────────

  group('debugLogFile — path resolution', () {
    test('returns null when debug is off', () {
      setDebugEnabled(false);
      expect(debugLogFile(environment: const {}), isNull);
    });

    test('returns default-path file when runtime flag is on', () {
      setDebugEnabled(true);
      final file = debugLogFile(environment: const {});
      expect(file, isNotNull);
      expect(file!.path, equals(kDefaultClaudartDebugLogPath));
    });

    test('honors CLAUDART_DEBUG_PATH override when set', () {
      setDebugEnabled(true);
      const overridePath = '/tmp/custom_claudart_debug.log';
      final file = debugLogFile(
        environment: const {kClaudartDebugPathEnvVarLiteral: overridePath},
      );
      expect(file, isNotNull);
      expect(file!.path, equals(overridePath));
    });

    test('env-only enable (no runtime flag) still produces a file', () {
      setDebugEnabled(false);
      final file = debugLogFile(
        environment: const {kClaudartDebugEnvVarLiteral: '1'},
      );
      expect(file, isNotNull);
      expect(file!.path, equals(kDefaultClaudartDebugLogPath));
    });
  });

  // ── setDebugEnabled is idempotent for tests ──────────────────────────────

  test('setDebugEnabled(false) clears the runtime flag', () {
    setDebugEnabled(true);
    expect(debugEnabled(environment: const {}), isTrue);
    setDebugEnabled(false);
    expect(debugEnabled(environment: const {}), isFalse);
  });

  // ── utf8ByteLength ──────────────────────────────────────────────────────

  group('utf8ByteLength returns real byte counts (not UTF-16 code units)',
      () {
    test('ASCII string: bytes == chars', () {
      expect(utf8ByteLength('hello'), equals(5));
    });

    test('multi-byte UTF-8: bytes > String.length', () {
      // The em dash '—' is a single Dart code unit but 3 bytes in UTF-8.
      const emDash = '—';
      expect(emDash.length, equals(1));
      expect(utf8ByteLength(emDash), equals(3));
    });

    test('empty string returns 0', () {
      expect(utf8ByteLength(''), equals(0));
    });
  });

  // ── StepDebugTrace ──────────────────────────────────────────────────────

  group('StepDebugTrace.disabled is a no-op', () {
    test('isActive is false', () {
      expect(StepDebugTrace.disabled().isActive, isFalse);
    });

    test('every write method is safe to call', () {
      // No assertion needed — the contract is "no throw, no write".
      final trace = StepDebugTrace.disabled();
      trace.writeStepHeader(
        modelAlias: 'haiku',
        workingDir: '/tmp',
        systemPrompt: 'sys',
        message: 'msg',
      );
      trace.writeStreamLine('line');
      trace.writeExit(exitCode: 0, stderrText: '');
      trace.writeSummary(
        modelAlias: 'haiku',
        systemPrompt: 'sys',
        message: 'msg',
        input: 1,
        cacheRead: 2,
        cacheCreation: 3,
        output: 4,
        cost: 0.0001,
        resultText: 'result',
      );
      trace.writeException(Exception('x'));
    });
  });

  group('StepDebugTrace.forTesting routes writes through the injected sink',
      () {
    test('every label + field declared in debug_mode appears in output', () {
      final buffer = StringBuffer();
      final trace = StepDebugTrace.forTesting(buffer.write);
      trace.writeStepHeader(
        modelAlias: 'haiku',
        workingDir: '/tmp',
        systemPrompt: 'sys-prompt',
        message: 'msg-body',
      );
      trace.writeStreamLine('streamed-line');
      trace.writeExit(exitCode: 0, stderrText: '');
      trace.writeSummary(
        modelAlias: 'haiku',
        systemPrompt: 'sys-prompt',
        message: 'msg-body',
        input: 10,
        cacheRead: 20,
        cacheCreation: 30,
        output: 40,
        cost: 0.05,
        resultText: 'final-text',
      );
      trace.writeException(Exception('boom'));
      final actual = buffer.toString();
      const labels = [
        kTraceLabelStep,
        kTraceLabelStream,
        kTraceLabelExit,
        kTraceLabelSummary,
        kTraceLabelOutputBytes,
        kTraceLabelException,
      ];
      for (final label in labels) {
        expect(actual, contains('$label: '),
            reason: 'expected label "$label" in trace output');
      }
      const fields = [
        kTraceFieldModel,
        kTraceFieldWorkingDir,
        kTraceFieldSysBytes,
        kTraceFieldMsgBytes,
        kTraceFieldInput,
        kTraceFieldCached,
        kTraceFieldCacheWrite,
        kTraceFieldOutput,
        kTraceFieldElapsedMs,
        kTraceFieldStderr,
      ];
      for (final field in fields) {
        expect(actual, contains(field),
            reason: 'expected field "$field" in trace output');
      }
      expect(actual, contains(kTraceStderrEmpty));
      expect(actual, contains(kTraceDividerSystemOpen));
      expect(actual, contains(kTraceDividerMessageOpen));
      expect(actual, contains(kTraceDividerEndInput));
    });

    test('empty stderr renders the sentinel; non-empty trims to text', () {
      final empty = StringBuffer();
      StepDebugTrace.forTesting(empty.write)
          .writeExit(exitCode: 0, stderrText: '   \n  ');
      expect(empty.toString(), contains(kTraceStderrEmpty));

      final nonEmpty = StringBuffer();
      StepDebugTrace.forTesting(nonEmpty.write)
          .writeExit(exitCode: 1, stderrText: '  oops  \n');
      expect(nonEmpty.toString(), contains('oops'));
      expect(nonEmpty.toString(), isNot(contains(kTraceStderrEmpty)));
    });

    test('summary line shows utf8 byte counts, not UTF-16 code units', () {
      const sysPrompt = '—'; // 1 code unit, 3 utf-8 bytes
      final buffer = StringBuffer();
      StepDebugTrace.forTesting(buffer.write).writeSummary(
        modelAlias: 'haiku',
        systemPrompt: sysPrompt,
        message: '',
        input: 0,
        cacheRead: 0,
        cacheCreation: 0,
        output: 0,
        cost: 0,
        resultText: '',
      );
      expect(buffer.toString(), contains('$kTraceFieldSysBytes=3'));
    });
  });

  group('best-effort write contract', () {
    test('disabled trace never throws — every method', () {
      expect(() {
        final trace = StepDebugTrace.disabled();
        trace.writeStepHeader(
            modelAlias: 'm', workingDir: '/', systemPrompt: '', message: '');
        trace.writeStreamLine('');
        trace.writeExit(exitCode: 0, stderrText: '');
        trace.writeSummary(
          modelAlias: 'm',
          systemPrompt: '',
          message: '',
          input: 0,
          cacheRead: 0,
          cacheCreation: 0,
          output: 0,
          cost: 0,
          resultText: '',
        );
        trace.writeException(Exception('x'));
      }, returnsNormally);
    });

    test('forTesting with a sink that throws — writeStepHeader propagates',
        () {
      // The IOException-swallow contract is specific to file IO via
      // [_appendToFile]. Sinks passed via [forTesting] are a test
      // affordance; they propagate their own exceptions so a buggy
      // test sink surfaces loudly rather than hiding behind the
      // best-effort wrapper. Documents the boundary.
      final trace = StepDebugTrace.forTesting((_) {
        throw const FormatException('sink error');
      });
      expect(
        () => trace.writeStreamLine('x'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

// ── Literal env-var name aliases used only by the path-override case ──────
//
// Map literals require const keys; importing them as `const` symbols
// from the production file produces compile-time-const maps without
// duplicating the string. If the production const renames, these
// references break the test at compile time — the desired coupling.

const String kClaudartDebugEnvVarLiteral = kClaudartDebugEnvVar;
const String kClaudartDebugPathEnvVarLiteral = kClaudartDebugPathEnvVar;
