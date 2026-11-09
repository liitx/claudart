// An interaction row can say what the run rested on (gap R16): the evidence a
// teardown found in the handoff, so a reminder says why it was one.

import 'dart:convert';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';

Map<String, dynamic> _row(MemoryFileIO io) => jsonDecode(io
    .read(logFilePath('$_workspace/logs', LogFile.interactions))
    .trim()) as Map<String, dynamic>;

void main() {
  late MemoryFileIO io;
  late SessionLogger logger;

  setUp(() {
    io = MemoryFileIO();
    logger = SessionLogger.plain(io: io, workspacePath: _workspace);
  });

  group('logInteraction evidence', () {
    test('is written when it is passed', () {
      logger.logInteraction(
        command: 'teardown',
        outcome: 'reminderSaved',
        evidence: 'debugUnrecorded',
      );
      expect(_row(io)[LogEntryField.evidence.name], 'debugUnrecorded');
    });

    test('is absent when it is not', () {
      logger.logInteraction(command: 'status', outcome: 'ok');
      expect(_row(io).containsKey(LogEntryField.evidence.name), isFalse);
    });
  });
}
