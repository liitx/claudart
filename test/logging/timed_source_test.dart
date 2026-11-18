// timed_source_test.dart — how long things took is read back from the logs by one
// typed reader, and every log is either read for timing or proven to hold none.
//
// The rows are written by the real writers, so the reader is proven against what
// claudart writes, not against rows invented here. Expected labels and durations
// are written out by hand. The template that says how to add a source
// (docs/templates/timed_source.md) must name every source and member.

import 'dart:convert';
import 'dart:io';

import 'package:claudart/config/paths.dart';
import 'package:claudart/io/gate_runner.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/logging/planner_log.dart';
import 'package:claudart/logging/timed_source.dart';
import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agents/categorization.dart';
import 'package:claudart/pipeline/model_observation.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';
final _logsDirectory = logsDirFor(_workspace);

SessionLogger _loggerOn(MemoryFileIO io) =>
    SessionLogger.plain(io: io, workspacePath: _workspace);

typedef _SourceCase = ({
  TimedSource source,
  String label,
  int durationMs,
  void Function(SessionLogger) write,
  void Function(SessionLogger)? writeOtherRow,
  Map<String, Object?> Function(Object? duration, Object? label) rawRow,
});

/// Each source: a row its real writer makes, what it must read back as, a row of
/// the same log that is not its own (where the log has one), and a hand-built
/// row whose duration and label can be broken one at a time.
final _cases = <_SourceCase>[
  (
    source: TimedSource.commandRun,
    label: 'debug',
    durationMs: 1234,
    write: (logger) => logger.logInteraction(
          rowKind: InteractionRowKind.run,
          command: 'debug',
          outcome: 'ok',
          durationMs: 1234,
        ),
    writeOtherRow: (logger) => logger.logInteraction(
          rowKind: InteractionRowKind.outcome,
          command: 'debug',
          outcome: 'ok',
          durationMs: 99,
        ),
    rawRow: (duration, label) => {
          LogEntryField.rowKind.name: InteractionRowKind.run.name,
          LogEntryField.command.name: label,
          LogEntryField.durationMs.name: duration,
        },
  ),
  (
    source: TimedSource.gateRun,
    label: GateKind.debugVerification.name,
    durationMs: 456,
    write: (logger) => logger.logGate(
          command: 'debug',
          gate: GateKind.debugVerification,
          shellCommand: 'dart test',
          result: const GateResult(
            exitCode: 0,
            outputTail: '',
            durationMs: 456,
          ),
        ),
    writeOtherRow: null,
    rawRow: (duration, label) => {
          LogEntryField.gate.name: label,
          LogEntryField.durationMs.name: duration,
        },
  ),
  (
    source: TimedSource.stepCompleted,
    label: 'reader',
    durationMs: 789,
    write: (logger) => logger.logPipelineEvent(
          command: 'debug',
          event: AgentCompleted(
            stepId: 'reader',
            usage: const Usage(),
            durationMs: 789,
          ),
        ),
    writeOtherRow: (logger) => logger.logPipelineEvent(
          command: 'debug',
          event: const AgentStarted(
            stepId: 'reader',
            label: 'Reading',
            model: AgentModel.haiku,
            displayStep: 1,
            displayTotal: 1,
          ),
        ),
    rawRow: (duration, label) => {
          LogEntryField.kind.name: PipelineEventKind.agentCompleted.name,
          LogEntryField.stepId.name: label,
          LogEntryField.detail.name: duration,
        },
  ),
  (
    source: TimedSource.proofFault,
    label: 'closureEvidence',
    durationMs: 321,
    write: (logger) => logger.logProofFault(
          proof: 'closureEvidence',
          fault: 'f',
          sourceFile: 'lib/a.dart',
          sourceLine: 1,
          verdict: ProofVerdict.caught,
          tier: 1,
          attempts: 1,
          caughtBy: const [],
          durationMs: 321,
        ),
    writeOtherRow: null,
    rawRow: (duration, label) => {
          LogEntryField.proof.name: label,
          LogEntryField.durationMs.name: duration,
        },
  ),
];

/// A duration or a label broken one way, and the reason the reader must give.
/// The duration is judged first, so a row missing both is a missing duration.
const _breaks = <({
  String name,
  Object? duration,
  Object? label,
  TimingGapReason reason,
})>[
  (
    name: 'no duration',
    duration: null,
    label: 'x',
    reason: TimingGapReason.durationMissing,
  ),
  (
    name: 'a duration that is text',
    duration: 'fast',
    label: 'x',
    reason: TimingGapReason.durationNotWholeNumber,
  ),
  (
    name: 'a fractional duration',
    duration: 1.5,
    label: 'x',
    reason: TimingGapReason.durationNotWholeNumber,
  ),
  (
    name: 'a negative duration',
    duration: -1,
    label: 'x',
    reason: TimingGapReason.durationNegative,
  ),
  (
    name: 'no label',
    duration: 5,
    label: null,
    reason: TimingGapReason.labelMissing,
  ),
  (
    name: 'neither duration nor label',
    duration: null,
    label: null,
    reason: TimingGapReason.durationMissing,
  ),
];

/// Logs that hold no timing, with why, written out here. A log that gains a
/// duration field must move to a [TimedSource] (the template says how).
const _untimedLogs = <LogFile, String>{
  LogFile.errors: 'a failure is a fact at a time, not a span',
  LogFile.transitions: 'a status move is instant',
  LogFile.models: 'what a step ran on, not how long it took',
  LogFile.planner: 'a routing decision is instant',
};

bool _looksTimed(String key) =>
    key.toLowerCase().contains('duration') || key.endsWith('Ms');

void main() {
  group('$TimedSource', () {
    for (final c in _cases) {
      group(c.source.name, () {
        late MemoryFileIO io;
        setUp(() => io = MemoryFileIO());

        test('reads the row its writer wrote as one record', () {
          c.write(_loggerOn(io));
          final reading = readTimedLog(io, _logsDirectory, c.source);
          expect(reading.gaps, isEmpty);
          expect(reading.records, [
            (source: c.source, label: c.label, durationMs: c.durationMs),
          ]);
        });

        final other = c.writeOtherRow;
        if (other != null) {
          test('reads nothing from a row of its log that is not its own', () {
            other(_loggerOn(io));
            final reading = readTimedLog(io, _logsDirectory, c.source);
            expect(reading.records, isEmpty);
            expect(reading.gaps, isEmpty);
          });
        }

        test('a log that does not exist reads as nothing, not as an error', () {
          final reading = readTimedLog(io, _logsDirectory, c.source);
          expect(reading.records, isEmpty);
          expect(reading.gaps, isEmpty);
        });

        test('reads records in the order they were written', () {
          final path = logFilePath(_logsDirectory, c.source.logFile);
          io.write(
            path,
            '${[
              for (final duration in [30, 10, 20])
                jsonEncode(c.rawRow(duration, c.label)),
            ].join('\n')}\n',
          );
          expect(
            [for (final r in readTimedLog(io, _logsDirectory, c.source).records) r.durationMs],
            [30, 10, 20],
          );
        });

        test('a duration of zero is a record, not a gap', () {
          io.write(
            logFilePath(_logsDirectory, c.source.logFile),
            '${jsonEncode(c.rawRow(0, c.label))}\n',
          );
          final reading = readTimedLog(io, _logsDirectory, c.source);
          expect(reading.gaps, isEmpty);
          expect(reading.records.single.durationMs, 0);
        });

        // At the largest cap any log has (5000), every other row broken: each is
        // read as a record or as a gap, none lost, and the order is kept.
        test('at 5000 rows, half of them broken, every row is a record or a gap',
            () {
          const rows = 5000;
          io.write(
            logFilePath(_logsDirectory, c.source.logFile),
            '${[
              for (var i = 0; i < rows; i++)
                jsonEncode(c.rawRow(i.isEven ? i : null, c.label)),
            ].join('\n')}\n',
          );
          final reading = readTimedLog(io, _logsDirectory, c.source);
          expect(reading.records, hasLength(rows ~/ 2));
          expect(reading.gaps, hasLength(rows ~/ 2));
          expect(reading.records.first.durationMs, 0);
          expect(reading.records.last.durationMs, rows - 2);
        });

        for (final broken in _breaks) {
          test('a row with ${broken.name} is a gap: ${broken.reason.name}', () {
            final row = c.rawRow(broken.duration, broken.label);
            io.write(
              logFilePath(_logsDirectory, c.source.logFile),
              '${jsonEncode(row)}\n',
            );
            final reading = readTimedLog(io, _logsDirectory, c.source);
            expect(reading.records, isEmpty);
            final gap = reading.gaps.single;
            expect(gap.source, c.source);
            expect(gap.reason, broken.reason);
            expect(gap.row, row);
          });
        }
      });
    }

    for (final source in TimedSource.values) {
      test('${source.name} has a case here', () {
        expect(_cases.map((c) => c.source), contains(source));
      });
    }
  });

  group('every log is timed or proven to hold no timing', () {
    final timedFiles = TimedSource.values.map((s) => s.logFile).toSet();

    for (final file in LogFile.values) {
      test('${file.name}: exactly one of read for timing or stated untimed', () {
        expect(timedFiles.contains(file) != _untimedLogs.containsKey(file), isTrue);
      });
    }

    final untimedRows = <LogFile, Map<String, dynamic> Function()>{
      LogFile.errors: () {
        final io = MemoryFileIO();
        _loggerOn(io).logError(
          command: 'x',
          errorType: 'e',
          fingerprint: 'f',
          reason: 'r',
        );
        return _lastRow(io, LogFile.errors);
      },
      LogFile.transitions: () {
        final io = MemoryFileIO();
        _loggerOn(io).logTransition(
          command: 'x',
          transition: const HandoffTransition(
            from: HandoffStatus.noHandoff,
            event: HandoffEvent.setup,
            to: HandoffStatus.suggestInvestigating,
          ),
        );
        return _lastRow(io, LogFile.transitions);
      },
      LogFile.models: () {
        final io = MemoryFileIO();
        _loggerOn(io).logStepModels(
          command: 'x',
          event: AgentCompleted(
            stepId: 'reader',
            usage: const Usage(),
            intendedModel: AgentModel.haiku,
            durationMs: 5,
            models: const [
              ModelObservation(observedModelId: 'claude-haiku-4-5-20251001'),
            ],
          ),
        );
        return _lastRow(io, LogFile.models);
      },
      LogFile.planner: () {
        final lines = <String>[];
        PlannerLog(path: '/ignored', appender: (_, line) => lines.add(line)).record(
          PlannerDecision(
            timestamp: DateTime.utc(2026, 11, 16),
            flow: AgentFlow.flow,
            category: AgentCategory.bug,
            intent: IntentClass.analyze,
            complexity: ComplexityTier.atomic,
            model: AgentModel.haiku,
            designSurfaceCounts: const {},
          ),
        );
        return jsonDecode(lines.single) as Map<String, dynamic>;
      },
    };

    for (final entry in _untimedLogs.entries) {
      test('${entry.key.name} writes no field that reads like a duration '
          '(${entry.value})', () {
        final row = untimedRows[entry.key]!();
        expect(row.keys.where(_looksTimed), isEmpty);
      });
    }

    test('every untimed log has a row to inspect', () {
      expect(untimedRows.keys.toSet(), _untimedLogs.keys.toSet());
    });
  });

  group('summarizeTimed', () {
    TimedRecord record(String label, int ms, [TimedSource source = TimedSource.commandRun]) =>
        (source: source, label: label, durationMs: ms);

    test('is empty for no records', () {
      expect(summarizeTimed(const []), isEmpty);
    });

    test('groups by source and label, in the order each first appears', () {
      final summaries = summarizeTimed([
        record('save', 40),
        record('debug', 100),
        record('save', 10),
        record('save', 70),
        record('save', 5, TimedSource.gateRun),
      ]);
      expect(summaries, [
        (source: TimedSource.commandRun, label: 'save', runs: 3, totalMs: 120, slowestMs: 70, latestMs: 70),
        (source: TimedSource.commandRun, label: 'debug', runs: 1, totalMs: 100, slowestMs: 100, latestMs: 100),
        (source: TimedSource.gateRun, label: 'save', runs: 1, totalMs: 5, slowestMs: 5, latestMs: 5),
      ]);
    });

    test('latest is the last one written, not the slowest', () {
      final summary = summarizeTimed([record('a', 90), record('a', 10)]).single;
      expect(summary.latestMs, 10);
      expect(summary.slowestMs, 90);
    });
  });

  group('the template', () {
    final template = File('docs/templates/timed_source.md').readAsStringSync();

    for (final source in TimedSource.values) {
      test('names ${source.name}', () {
        expect(template, contains('`${source.name}`'));
      });
    }

    for (final member in const [
      'logFile',
      'qualifies',
      'rawDurationOf',
      'labelOf',
    ]) {
      test('names the required member $member', () {
        expect(template, contains('`$member`'));
      });
    }

    for (final reason in TimingGapReason.values) {
      test('names the gap reason ${reason.name}', () {
        expect(template, contains('`${reason.name}`'));
      });
    }
  });
}

Map<String, dynamic> _lastRow(MemoryFileIO io, LogFile file) => jsonDecode(
      io
          .read(logFilePath(_logsDirectory, file))
          .trim()
          .split('\n')
          .last,
    ) as Map<String, dynamic>;
