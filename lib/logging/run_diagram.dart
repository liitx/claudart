// run_diagram.dart — a run, drawn from the logs it left
//
// One Mermaid sequence diagram per command run: the owner starts the command,
// the command moves the handoff and calls models, and the run ends. A run is a
// boundary row of the interactions log (the one with a duration); the rows of
// the transitions, steps and errors logs that fall inside its window under the
// same command belong to it. Nothing is read but what the logs already hold, so
// a step missing from a diagram is a step the logs did not record.

import 'dart:convert';

import '../pipeline/pipeline_event.dart';
import '../session/handoff_transition.dart';
import 'logger.dart';
import 'recorded_outcome.dart';

/// The rows of a JSONL log: each line that is a JSON object. A blank line, a
/// broken line and a line that is not an object are skipped, so one bad write
/// does not hide the rest of a log.
List<Map<String, dynamic>> rowsOfJsonl(String text) {
  final rows = <Map<String, dynamic>>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) rows.add(decoded);
    } on FormatException {
      continue;
    }
  }
  return rows;
}

/// One command run and the rows of the other logs that belong to it.
class RunLog {
  const RunLog({
    required this.command,
    required this.startedAt,
    required this.endedAt,
    required this.outcome,
    required this.durationMs,
    required this.transitions,
    required this.steps,
    required this.errors,
  });

  final String command;
  final DateTime startedAt;
  final DateTime endedAt;
  final String outcome;
  final int durationMs;
  final List<Map<String, dynamic>> transitions;
  final List<Map<String, dynamic>> steps;
  final List<Map<String, dynamic>> errors;
}

/// The runs in the given log rows, oldest first. A row of [interactions] with
/// no `durationMs` was written by a command itself, not by the boundary, and is
/// not a run.
List<RunLog> runsFrom({
  required List<Map<String, dynamic>> interactions,
  required List<Map<String, dynamic>> transitions,
  required List<Map<String, dynamic>> steps,
  required List<Map<String, dynamic>> errors,
}) {
  final runs = <RunLog>[];
  for (final row in interactions) {
    final durationMs = row[LogEntryField.durationMs.name];
    if (durationMs is! int) continue;
    final endedAt = _timeOf(row);
    final startedAt = endedAt.subtract(Duration(milliseconds: durationMs));
    final command = row[LogEntryField.command.name] as String;
    List<Map<String, dynamic>> inside(List<Map<String, dynamic>> rows) => [
          for (final candidate in rows)
            if (candidate[LogEntryField.command.name] == command &&
                !_timeOf(candidate).isBefore(startedAt) &&
                !_timeOf(candidate).isAfter(endedAt))
              candidate,
        ];
    runs.add(RunLog(
      command: command,
      startedAt: startedAt,
      endedAt: endedAt,
      outcome: row[LogEntryField.outcome.name] as String,
      durationMs: durationMs,
      transitions: inside(transitions),
      steps: inside(steps),
      errors: inside(errors),
    ));
  }
  return runs..sort((a, b) => a.endedAt.compareTo(b.endedAt));
}

DateTime _timeOf(Map<String, dynamic> row) =>
    DateTime.parse(row[LogEntryField.ts.name] as String);

/// The people and things a run talks to, as the diagram names them.
enum _Participant {
  owner('Owner', 'Owner'),
  command('Command', null),
  handoff('Handoff', 'Handoff'),
  model('Model', 'Model');

  const _Participant(this.id, this.label);
  final String id;
  final String? label;
}

/// Text from a log made safe to put after a Mermaid message colon: no line
/// breaks, no statement separator, no entity marker, and not unbounded.
String _safe(Object? text) {
  final cleaned = '$text'
      .replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ')
      .replaceAll(';', ',')
      .replaceAll('#', '');
  return cleaned.length > 120 ? '${cleaned.substring(0, 119)}…' : cleaned;
}

/// A step's detail as the diagram says it: the log writes a completed step's
/// duration as an integer of milliseconds, anything else is text.
String _durationOrText(Object detail) =>
    detail is int ? '${detail}ms' : _safe(detail);

/// The Mermaid sequence diagram of [run].
String renderRunDiagram(RunLog run) {
  final owner = _Participant.owner.id;
  final command = _Participant.command.id;
  final handoff = _Participant.handoff.id;
  final model = _Participant.model.id;

  final timed = <(DateTime, int, String)>[];
  var order = 0;
  void add(Map<String, dynamic> row, String line) =>
      timed.add((_timeOf(row), order++, line));

  for (final row in run.transitions) {
    final from = row[HandoffTransitionField.from.name];
    final event = row[HandoffTransitionField.event.name];
    final to = row[HandoffTransitionField.to.name];
    add(
      row,
      row[LogEntryField.rejected.name] == true
          ? '$command--x$handoff: ${_safe(event)} rejected from ${_safe(from)}'
          : '$command->>$handoff: ${_safe(event)}: ${_safe(from)} → ${_safe(to)}',
    );
  }
  for (final row in run.steps) {
    final kind = row[LogEntryField.kind.name];
    final step = _safe(row[LogEntryField.stepId.name] ?? '');
    final Object? detail = row[LogEntryField.detail.name];
    final failureType = row[LogEntryField.failureType.name];
    add(
      row,
      switch (kind) {
        _ when kind == PipelineEventKind.agentStarted.name =>
          '$command->>$model: $step started',
        _ when kind == PipelineEventKind.agentCompleted.name =>
          '$model-->>$command: $step completed'
              '${detail == null ? '' : ' (${_durationOrText(detail)})'}',
        _ when kind == PipelineEventKind.agentFailed.name =>
          '$model--x$command: $step failed: ${_safe(failureType ?? detail ?? '')}',
        _ => 'Note over $command,$model: ${_safe(kind)} $step',
      },
    );
  }
  for (final row in run.errors) {
    add(row, 'Note over $command: error ${_safe(row[LogEntryField.fingerprint.name])}');
  }
  timed.sort((a, b) {
    final byTime = a.$1.compareTo(b.$1);
    return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
  });

  final ended = run.outcome == RecordedOutcome.ok.name
      ? '$command-->>$owner: ${_safe(run.outcome)} after ${run.durationMs}ms'
      : '$command--x$owner: ${_safe(run.outcome)} after ${run.durationMs}ms';

  return [
    'sequenceDiagram',
    '    participant $owner',
    '    participant $command as claudart ${_safe(run.command)}',
    '    participant $handoff',
    '    participant $model',
    '    $owner->>$command: claudart ${_safe(run.command)}',
    for (final (_, _, line) in timed) '    $line',
    '    $ended',
    '',
  ].join('\n');
}

/// A markdown page with a heading and a fenced diagram for each run.
String renderRunPage(List<RunLog> runs) {
  if (runs.isEmpty) return '# Runs\n\nNo runs were recorded.\n';
  final buffer = StringBuffer('# Runs\n');
  for (final run in runs) {
    buffer
      ..writeln()
      ..writeln('## ${run.command} — ${run.endedAt.toUtc().toIso8601String()}')
      ..writeln()
      ..writeln('```mermaid')
      ..write(renderRunDiagram(run))
      ..writeln('```');
  }
  return buffer.toString();
}

const String _mermaidModule =
    'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// A web page that draws each run: the diagrams are text in `pre.mermaid`
/// blocks and the page loads Mermaid to draw them when it is opened. What the
/// logs wrote is escaped, so it cannot become markup.
String renderRunHtml(List<RunLog> runs) {
  final body = StringBuffer();
  if (runs.isEmpty) {
    body.writeln('<p>No runs were recorded.</p>');
  }
  for (final run in runs) {
    body
      ..writeln('<h2>${_escapeHtml(run.command)} — '
          '${run.endedAt.toUtc().toIso8601String()}</h2>')
      ..writeln('<pre class="mermaid">')
      ..write(_escapeHtml(renderRunDiagram(run)))
      ..writeln('</pre>');
  }
  return '''<!doctype html>
<meta charset="utf-8">
<title>claudart runs</title>
<style>body{font-family:system-ui,sans-serif;margin:2rem}h2{margin-top:2.5rem}</style>
<h1>Runs</h1>
$body<script type="module">
import mermaid from '$_mermaidModule';
mermaid.initialize({startOnLoad: true});
</script>
''';
}
