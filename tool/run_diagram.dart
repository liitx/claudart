// run_diagram — draws the runs the logs hold, as Mermaid sequence diagrams.
//
//   dart run tool/run_diagram.dart <logs-dir>... [--command=<name>] [--html=<file>]
//   dart run tool/run_diagram.dart --trace=<trace-file> [--html=<file>]
//   make diagram DIR="<global-logs> <workspace-logs>" [CMD=debug] [HTML=<file>]
//   make diagram TRACE=<trace-file> [HTML=<file>]
//
// With --trace the page draws what the tests did (CLAUDART_TEST_TRACE, see
// test/helpers/test_trace.dart): the input, the expectation, the answer and the
// log rows each check caused, counted by spec obligation.
//
// A run's boundary row is in the global log and its handoff moves, steps and
// errors are in its project's, so pass both directories to see a whole run.
// Without --html the page is markdown on stdout; with it, a web page that
// draws the diagrams when opened.

import 'dart:io';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/run_diagram.dart';
import 'package:claudart/logging/trace_diagram.dart';

const _commandPrefix = '--command=';
const _htmlPrefix = '--html=';
const _tracePrefix = '--trace=';

List<Map<String, dynamic>> _rows(List<String> directories, LogFile file) => [
      for (final directory in directories)
        if (File(logFilePath(directory, file)).existsSync())
          ...rowsOfJsonl(File(logFilePath(directory, file)).readAsStringSync()),
    ];

void main(List<String> args) {
  final tracePath = args
      .where((arg) => arg.startsWith(_tracePrefix))
      .map((arg) => arg.substring(_tracePrefix.length))
      .firstOrNull;
  if (tracePath != null) {
    final htmlFile = args
        .where((arg) => arg.startsWith(_htmlPrefix))
        .map((arg) => arg.substring(_htmlPrefix.length))
        .firstOrNull;
    final rows = traceRowsOfJsonl(
      File(tracePath).existsSync() ? File(tracePath).readAsStringSync() : '',
    );
    if (htmlFile == null) {
      stdout.write(renderTracePage(rows));
    } else {
      File(htmlFile).writeAsStringSync(renderTraceHtml(rows));
      stdout.writeln('wrote $htmlFile (${rows.length} checks)');
    }
    return;
  }
  final directories = [for (final arg in args) if (!arg.startsWith('--')) arg];
  if (directories.isEmpty) {
    stderr.writeln('usage: dart run tool/run_diagram.dart <logs-dir>... '
        '[--command=<name>] [--html=<file>]');
    exit(2);
  }
  String? option(String prefix) => args
      .where((arg) => arg.startsWith(prefix))
      .map((arg) => arg.substring(prefix.length))
      .firstOrNull;
  final command = option(_commandPrefix);
  final htmlPath = option(_htmlPrefix);

  final runs = runsFrom(
    interactions: _rows(directories, LogFile.interactions),
    transitions: _rows(directories, LogFile.transitions),
    steps: _rows(directories, LogFile.steps),
    errors: _rows(directories, LogFile.errors),
    gates: _rows(directories, LogFile.gates),
  ).where((run) => command == null || run.command == command).toList();

  if (htmlPath == null) {
    stdout.write(renderRunPage(runs));
  } else {
    File(htmlPath).writeAsStringSync(renderRunHtml(runs));
    stdout.writeln('wrote $htmlPath (${runs.length} runs)');
  }
}
