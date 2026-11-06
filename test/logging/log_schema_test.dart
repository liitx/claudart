// Every row a log writes names the schema it follows (gap R7), so a reader of a
// log that changed shape over time can tell an old row from a current one: a
// row without the field predates it.

import 'dart:convert';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/model_observation.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';
const _command = 'status';

/// A way of writing one row, and the log it lands in.
typedef _Writer = ({String name, LogFile file, void Function(SessionLogger) write});

final _writers = <_Writer>[
  (
    name: 'an interaction',
    file: LogFile.interactions,
    write: (logger) => logger.logInteraction(command: _command, outcome: 'ok'),
  ),
  (
    name: 'a transition',
    file: LogFile.transitions,
    write: (logger) => logger.logTransition(
      command: _command,
      transition: const HandoffTransition(
        from: HandoffStatus.readyForDebug,
        event: HandoffEvent.debugStarted,
        to: HandoffStatus.debugInProgress,
      ),
    ),
  ),
  (
    name: 'a rejected move',
    file: LogFile.transitions,
    write: (logger) => logger.logHandoffMove(
      command: _command,
      from: HandoffStatus.suggestInvestigating,
      event: HandoffEvent.tornDown,
    ),
  ),
  (
    name: 'an error',
    file: LogFile.errors,
    write: (logger) => logger.logError(
      command: _command,
      errorType: 'session',
      fingerprint: 'session.test',
      reason: 'a reason',
    ),
  ),
  (
    name: 'a pipeline step',
    file: LogFile.steps,
    write: (logger) => logger.logPipelineEvent(
      command: _command,
      event: const AgentStarted(
        stepId: 'reader',
        label: 'Reading',
        model: AgentModel.haiku,
        displayStep: 1,
        displayTotal: 2,
      ),
    ),
  ),
  (
    name: 'a step model record',
    file: LogFile.models,
    write: (logger) => logger.logStepModels(
      command: _command,
      event: AgentCompleted(
        stepId: 'reader',
        usage: const Usage(),
        intendedModel: AgentModel.haiku,
        models: const [
          ModelObservation(observedModelId: 'claude-haiku-4-5-20251001'),
        ],
      ),
    ),
  ),
];

Map<String, dynamic> _lastRow(MemoryFileIO io, LogFile file) {
  final path = logFilePath('$_workspace/logs', file);
  final lines = io
      .read(path)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  return jsonDecode(lines.last) as Map<String, dynamic>;
}

void main() {
  group('log schema version', () {
    for (final writer in _writers) {
      test('${writer.name} names the schema it follows', () {
        final io = MemoryFileIO();
        writer.write(SessionLogger.plain(io: io, workspacePath: _workspace));
        expect(
          _lastRow(io, writer.file)[LogEntryField.schema.name],
          logSchemaVersion,
        );
      });
    }

    test('the version is a positive whole number', () {
      expect(logSchemaVersion, greaterThan(0));
    });
  });
}
