// A run, drawn from the logs it left (visibility: what ran, in what order, and
// how it ended). The diagram is built only from rows the logs already hold, so
// whatever is missing from it is missing from the logs.

import 'package:claudart/logging/run_diagram.dart';
import 'package:test/test.dart';

Map<String, dynamic> _boundary(String ts, String command, String outcome, int ms) =>
    {'ts': ts, 'command': command, 'outcome': outcome, 'durationMs': ms};

Map<String, dynamic> _move(String ts, String command, String from, String event,
        {String? to}) =>
    {
      'ts': ts,
      'command': command,
      'from': from,
      'event': event,
      if (to != null) 'to': to else 'rejected': true,
    };

/// A step row. The real log writes the duration of a completed step as an
/// integer of milliseconds, so [detail] is any JSON value.
Map<String, dynamic> _step(String ts, String command, String kind,
        {String? stepId, Object? detail, String? failureType}) =>
    {
      'ts': ts,
      'command': command,
      'kind': kind,
      if (stepId != null) 'stepId': stepId,
      if (detail != null) 'detail': detail,
      if (failureType != null) 'failureType': failureType,
    };

const _t0 = '2026-11-06T10:00:00.000Z';

void main() {
  group('a run', () {
    test('is drawn in the order its rows happened', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'debug', 'ok', 5000)],
        transitions: [
          _move('2026-11-06T10:00:04.000Z', 'debug', 'debugInProgress', 'fixApplied',
              to: 'debugComplete'),
          _move('2026-11-06T10:00:01.000Z', 'debug', 'readyForDebug', 'debugStarted',
              to: 'debugInProgress'),
        ],
        steps: [
          _step('2026-11-06T10:00:02.000Z', 'debug', 'agentStarted', stepId: 'reader'),
          _step('2026-11-06T10:00:03.000Z', 'debug', 'agentCompleted',
              stepId: 'reader', detail: 1200),
        ],
        errors: const [],
      );
      expect(runs, hasLength(1));
      expect(renderRunDiagram(runs.single), '''sequenceDiagram
    participant Owner
    participant Command as claudart debug
    participant Handoff
    participant Model
    Owner->>Command: claudart debug
    Command->>Handoff: debugStarted: readyForDebug → debugInProgress
    Command->>Model: reader started
    Model-->>Command: reader completed (1200ms)
    Command->>Handoff: fixApplied: debugInProgress → debugComplete
    Command-->>Owner: ok after 5000ms
''');
    });

    test('takes only the rows inside its window and under its command', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'debug', 'ok', 2000)],
        transitions: [
          _move('2026-11-06T09:00:00.000Z', 'debug', 'a', 'earlier', to: 'b'),
          _move('2026-11-06T10:00:04.000Z', 'debug', 'x', 'inside', to: 'y'),
          _move('2026-11-06T10:00:04.500Z', 'save', 'x', 'otherCommand', to: 'y'),
        ],
        steps: const [],
        errors: const [],
      );
      final text = renderRunDiagram(runs.single);
      expect(text, contains('inside'));
      expect(text, isNot(contains('earlier')));
      expect(text, isNot(contains('otherCommand')));
    });

    test('shows a move the table lacks as rejected', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'kill', 'ok', 5000)],
        transitions: [
          _move('2026-11-06T10:00:01.000Z', 'kill', 'suggestInvestigating', 'tornDown'),
        ],
        steps: const [],
        errors: const [],
      );
      expect(renderRunDiagram(runs.single),
          contains('Command--xHandoff: tornDown rejected from suggestInvestigating'));
    });

    test('shows a failed step with its failure type', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'debug', 'failed', 5000)],
        transitions: const [],
        steps: [
          _step('2026-11-06T10:00:02.000Z', 'debug', 'agentFailed',
              stepId: 'implementer', failureType: 'stepTimedOut'),
        ],
        errors: const [],
      );
      final text = renderRunDiagram(runs.single);
      expect(text, contains('Model--xCommand: implementer failed: stepTimedOut'));
      expect(text, contains('Command--xOwner: failed after 5000ms'));
    });

    test('shows an error logged during the run', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'debug', 'failed', 5000)],
        transitions: const [],
        steps: const [],
        errors: [
          {
            'ts': '2026-11-06T10:00:03.000Z',
            'command': 'debug',
            'fingerprint': 'pipeline.implementer.stepTimedOut',
            'reason': 'timed out',
          },
        ],
      );
      expect(renderRunDiagram(runs.single),
          contains('Note over Command: error pipeline.implementer.stepTimedOut'));
    });

    test('with nothing logged inside it is only the command and its outcome',
        () {
      final runs = runsFrom(
        interactions: [_boundary(_t0, 'status', 'ok', 15)],
        transitions: const [],
        steps: const [],
        errors: const [],
      );
      expect(renderRunDiagram(runs.single), '''sequenceDiagram
    participant Owner
    participant Command as claudart status
    participant Handoff
    participant Model
    Owner->>Command: claudart status
    Command-->>Owner: ok after 15ms
''');
    });
  });

  group('runs', () {
    test('one run for each boundary row, oldest first', () {
      final runs = runsFrom(
        interactions: [
          _boundary('2026-11-06T11:00:00.000Z', 'save', 'ok', 10),
          _boundary('2026-11-06T10:00:00.000Z', 'status', 'ok', 10),
        ],
        transitions: const [],
        steps: const [],
        errors: const [],
      );
      expect(runs.map((run) => run.command), ['status', 'save']);
    });

    test('a row a command wrote itself, with no duration, is not a run', () {
      final runs = runsFrom(
        interactions: [
          {'ts': _t0, 'command': 'doctor', 'outcome': 'failed'},
        ],
        transitions: const [],
        steps: const [],
        errors: const [],
      );
      expect(runs, isEmpty);
    });
  });

  group('text from the logs', () {
    test('cannot break the diagram', () {
      final runs = runsFrom(
        interactions: [_boundary('2026-11-06T10:00:05.000Z', 'debug', 'ok', 5000)],
        transitions: const [],
        steps: [
          _step('2026-11-06T10:00:02.000Z', 'debug', 'agentCompleted',
              stepId: 'a;b', detail: 'one\ntwo # three'),
        ],
        errors: const [],
      );
      final text = renderRunDiagram(runs.single);
      expect(text, isNot(contains('a;b')));
      expect(text, isNot(contains('#')));
      expect(text, isNot(contains('one\ntwo')));
    });
  });

  group('reading a log', () {
    test('takes each line as a row and skips blank and broken lines', () {
      final rows = rowsOfJsonl('{"a":1}\n\nnot json\n{"b":2}\n');
      expect(rows, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('a line that is JSON but not an object is skipped', () {
      expect(rowsOfJsonl('[1,2]\n"text"\n{"a":1}\n'), [
        {'a': 1},
      ]);
    });

    test('an empty log has no rows', () {
      expect(rowsOfJsonl(''), isEmpty);
    });
  });

  group('the html page', () {
    final runs = runsFrom(
      interactions: [_boundary(_t0, 'status', 'ok', 15)],
      transitions: const [],
      steps: const [],
      errors: const [],
    );

    test('holds each diagram for Mermaid to draw, and loads Mermaid', () {
      final html = renderRunHtml(runs);
      expect(html, contains('<pre class="mermaid">\nsequenceDiagram'));
      expect(html, contains('mermaid'));
      expect(html, contains('<script type="module">'));
      expect(html, contains('status'));
    });

    test('escapes what the logs wrote so it cannot become markup', () {
      final hostile = runsFrom(
        interactions: [_boundary(_t0, 'a<b>&c', 'ok', 15)],
        transitions: const [],
        steps: const [],
        errors: const [],
      );
      final html = renderRunHtml(hostile);
      expect(html, isNot(contains('a<b>')));
      expect(html, contains('a&lt;b&gt;&amp;c'));
    });

    test('says so when there are no runs', () {
      expect(renderRunHtml(const []), contains('No runs'));
    });
  });

  group('the page', () {
    test('has a heading and a fenced diagram for each run', () {
      final page = renderRunPage(
        runsFrom(
          interactions: [_boundary(_t0, 'status', 'ok', 15)],
          transitions: const [],
          steps: const [],
          errors: const [],
        ),
      );
      expect(page, contains('## status — 2026-11-06T10:00:00.000Z'));
      expect(page, contains('```mermaid\nsequenceDiagram'));
      expect(page, endsWith('```\n'));
    });

    test('says so when there are no runs', () {
      expect(renderRunPage(const []), contains('No runs'));
    });
  });
}
