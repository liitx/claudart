// run_diagram — draws the runs a logs directory holds, as a markdown page of
// Mermaid sequence diagrams.
//
//   dart run tool/run_diagram.dart <logs-dir> [command]      (or: make diagram DIR=...)
//
// <logs-dir> is a workspace's `logs/` or the global one. With [command] only
// that command's runs are drawn.

import 'dart:io';

import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart' show LogEntryField;
import 'package:claudart/logging/run_diagram.dart';

List<Map<String, dynamic>> _rows(String directory, LogFile file) {
  final path = logFilePath(directory, file);
  return File(path).existsSync()
      ? rowsOfJsonl(File(path).readAsStringSync())
      : const [];
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/run_diagram.dart <logs-dir> [command]');
    exit(2);
  }
  final directory = args.first;
  final command = args.length > 1 ? args[1] : null;
  final runs = runsFrom(
    interactions: _rows(directory, LogFile.interactions),
    transitions: _rows(directory, LogFile.transitions),
    steps: _rows(directory, LogFile.steps),
    errors: _rows(directory, LogFile.errors),
  ).where((run) => command == null || run.command == command).toList();
  stdout.write(renderRunPage(runs));
  if (runs.isEmpty) {
    stderr.writeln('no runs in $directory (${LogEntryField.durationMs.name} rows)');
  }
}
