// A gate run is logged in full (gap R15): which gate, the command, how it
// ended, how long it took and the tail of its output.

import 'dart:convert';

import 'package:claudart/io/gate_runner.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';

List<Map<String, dynamic>> _rows(MemoryFileIO io) => [
      for (final line in io
          .read(logFilePath('$_workspace/logs', LogFile.gates))
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

  group('logGate', () {
    test('writes one row with the gate, the command and how it ended', () {
      logger.logGate(
        command: 'debug',
        gate: GateKind.debugVerification,
        shellCommand: 'dart test',
        result: const GateResult(
          exitCode: 1,
          outputTail: 'Some tests failed',
          durationMs: 5400,
        ),
      );
      final row = _rows(io).single;
      expect(row['schema'], logSchemaVersion);
      expect(row['command'], 'debug');
      expect(row['gate'], GateKind.debugVerification.name);
      expect(row['shellCommand'], 'dart test');
      expect(row['exitCode'], 1);
      expect(row['durationMs'], 5400);
      expect(row['outputTail'], 'Some tests failed');
    });

    test('a passing gate is logged too', () {
      logger.logGate(
        command: 'rotate',
        gate: GateKind.rotateBuild,
        shellCommand: 'make rebuild',
        result: const GateResult(exitCode: 0, outputTail: '', durationMs: 90),
      );
      expect(_rows(io).single['exitCode'], 0);
      expect(_rows(io).single['gate'], GateKind.rotateBuild.name);
    });

    test('every gate kind is logged under its own name', () {
      expect(GateKind.values.map((kind) => kind.name).toSet(),
          {'debugVerification', 'rotateBuild'});
    });
  });
}
