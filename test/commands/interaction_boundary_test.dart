// Every command run leaves one interaction record (Q5, gap R1, R11). The
// boundary that runs a command records how it ended: it returned, it threw, or
// it left the process through `exitProcess`. A matrix over ClaudartCommand
// proves no command is outside it.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/commands/support/claudart_command.dart';
import 'package:claudart/commands/support/interaction_boundary.dart';
import 'package:claudart/io/process_exit.dart';
import 'package:claudart/logging/logger.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';

class _Left implements Exception {
  _Left(this.code);
  final int code;
}

Never _leave(int code) => throw _Left(code);

List<Map<String, dynamic>> _rows(MemoryFileIO io) {
  final path = '$_workspace/logs/interactions.jsonl';
  if (!io.fileExists(path)) return [];
  return [
    for (final line in io.read(path).split('\n'))
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
}

({MemoryFileIO io, SessionLogger logger}) _fixture() {
  final io = MemoryFileIO();
  return (
    io: io,
    logger: SessionLogger.plain(io: io, workspacePath: _workspace),
  );
}

void main() {
  group('a command that returns', () {
    for (final command in ClaudartCommand.values) {
      test('${command.name} leaves one ok record under its wire name', () async {
        final fixture = _fixture();
        await runRecorded(
          command: command,
          logger: fixture.logger,
          leave: _leave,
          body: () async {},
        );
        final rows = _rows(fixture.io);
        expect(rows, hasLength(1));
        expect(rows.single['command'], command.wireName);
        expect(rows.single['outcome'], RecordedOutcome.ok.name);
      });
    }

    test('the record carries how long the run took', () async {
      final fixture = _fixture();
      await runRecorded(
        command: ClaudartCommand.status,
        logger: fixture.logger,
        leave: _leave,
        body: () async {},
      );
      expect(_rows(fixture.io).single['durationMs'], isA<int>());
    });

    test('its result is returned', () async {
      final fixture = _fixture();
      final result = await runRecorded(
        command: ClaudartCommand.status,
        logger: fixture.logger,
        leave: _leave,
        body: () async => 7,
      );
      expect(result, 7);
    });
  });

  group('a command that throws', () {
    test('leaves one failed record and the error goes on', () async {
      final fixture = _fixture();
      await expectLater(
        runRecorded(
          command: ClaudartCommand.save,
          logger: fixture.logger,
          leave: _leave,
          body: () async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      final rows = _rows(fixture.io);
      expect(rows, hasLength(1));
      expect(rows.single['outcome'], RecordedOutcome.failed.name);
    });
  });

  group('a command that leaves the process', () {
    test('an exit with 0 is recorded ok before the process leaves', () async {
      final fixture = _fixture();
      await expectLater(
        runRecorded(
          command: ClaudartCommand.status,
          logger: fixture.logger,
          leave: _leave,
          body: () async => exitProcess(0),
        ),
        throwsA(isA<_Left>().having((e) => e.code, 'code', 0)),
      );
      final rows = _rows(fixture.io);
      expect(rows, hasLength(1));
      expect(rows.single['outcome'], RecordedOutcome.ok.name);
    });

    test('an exit with a code is recorded failed', () async {
      final fixture = _fixture();
      await expectLater(
        runRecorded(
          command: ClaudartCommand.kill,
          logger: fixture.logger,
          leave: _leave,
          body: () async => exitProcess(2),
        ),
        throwsA(isA<_Left>().having((e) => e.code, 'code', 2)),
      );
      expect(_rows(fixture.io).single['outcome'], RecordedOutcome.failed.name);
    });

    test('a run that exits and is then unwound records once', () async {
      final fixture = _fixture();
      await expectLater(
        runRecorded(
          command: ClaudartCommand.kill,
          logger: fixture.logger,
          leave: _leave,
          body: () async => exitProcess(1),
        ),
        throwsA(isA<_Left>()),
      );
      expect(_rows(fixture.io), hasLength(1));
    });
  });

  group('exitProcess', () {
    test('outside a recorded run it only leaves', () {
      expect(() => exitProcessWith(5, leave: _leave), throwsA(isA<_Left>()));
    });

    test('after a recorded run it no longer records', () async {
      final fixture = _fixture();
      await runRecorded(
        command: ClaudartCommand.status,
        logger: fixture.logger,
        leave: _leave,
        body: () async {},
      );
      expect(() => exitProcessWith(1, leave: _leave), throwsA(isA<_Left>()));
      expect(_rows(fixture.io), hasLength(1));
    });
  });

  group('the binary', () {
    final bin = File('bin/claudart.dart').readAsStringSync();

    test('runs the chosen command only inside runRecorded', () {
      final calls = RegExp(r'_dispatch\(').allMatches(bin).toList();
      // The one call, then the definition.
      expect(calls, hasLength(2));
      final call = calls.first.start;
      expect(bin.substring(call - 260, call), contains('runRecorded('));
    });
  });
}
