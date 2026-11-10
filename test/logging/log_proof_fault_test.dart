// A seeded fault is logged with where it was seeded and what caught it, so the
// audit of the proofs can say which proof is weak and at which line.

import 'dart:convert';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';

List<Map<String, dynamic>> _rows(MemoryFileIO io) => [
      for (final line in io
          .read(logFilePath('$_workspace/logs', LogFile.proofs))
          .split('\n')
          .where((line) => line.trim().isNotEmpty))
        jsonDecode(line) as Map<String, dynamic>,
    ];

void main() {
  late MemoryFileIO io;
  late SessionLogger logger;

  setUp(() {
    io = MemoryFileIO();
    logger = SessionLogger.plain(io: io, workspacePath: _workspace);
  });

  void log(ProofVerdict verdict, {List<String> caughtBy = const []}) =>
      logger.logProofFault(
        proof: 'transitionTable',
        fault: 'noHandoff x setup: suggestInvestigating -> unknown',
        sourceFile: 'lib/session/session_state.dart',
        sourceLine: 148,
        verdict: verdict,
        tier: 1,
        caughtBy: caughtBy,
        durationMs: 4200,
      );

  group('logProofFault', () {
    test('writes one row saying what was seeded, where and how it ended', () {
      log(ProofVerdict.caught, caughtBy: ['P9 replay']);
      final row = _rows(io).single;
      expect(row['schema'], logSchemaVersion);
      expect(row['proof'], 'transitionTable');
      expect(row['fault'], 'noHandoff x setup: suggestInvestigating -> unknown');
      expect(row['sourceFile'], 'lib/session/session_state.dart');
      expect(row['sourceLine'], 148);
      expect(row['verdict'], 'caught');
      expect(row['tier'], 1);
      expect(row['caughtBy'], ['P9 replay']);
      expect(row['durationMs'], 4200);
    });

    for (final verdict in ProofVerdict.values) {
      test('a ${verdict.name} fault is logged under its own name', () {
        log(verdict);
        expect(_rows(io).single['verdict'], verdict.name);
      });
    }

    test('a missed fault names no test, because none failed', () {
      log(ProofVerdict.missed);
      expect(_rows(io).single['caughtBy'], isEmpty);
    });
  });
}
