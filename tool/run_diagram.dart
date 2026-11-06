// run_diagram — draws the runs the logs hold, as Mermaid sequence diagrams.
//
//   dart run tool/run_diagram.dart <logs-dir>... [--command=<name>] [--html=<file>]
//   make diagram DIR="<global-logs> <workspace-logs>" [CMD=debug] [HTML=<file>]
//
// A run's boundary row is in the global log and its handoff moves, steps and
// errors are in its project's, so pass both directories to see a whole run.
// Without --html the page is markdown on stdout; with it, a web page that
// draws the diagrams when opened.

import 'dart:io';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/run_diagram.dart';

const _commandPrefix = '--command=';
const _htmlPrefix = '--html=';

List<Map<String, dynamic>> _rows(List<String> directories, LogFile file) => [
      for (final directory in directories)
        if (File(logFilePath(directory, file)).existsSync())
          ...rowsOfJsonl(File(logFilePath(directory, file)).readAsStringSync()),
    ];

void main(List<String> args) {
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
  ).where((run) => command == null || run.command == command).toList();

  if (htmlPath == null) {
    stdout.write(renderRunPage(runs));
  } else {
    File(htmlPath).writeAsStringSync(renderRunHtml(runs));
    stdout.writeln('wrote $htmlPath (${runs.length} runs)');
  }
}
