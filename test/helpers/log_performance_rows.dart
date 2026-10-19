// log_performance_rows.dart — a child process for the concurrent
// logPerformance test: logs [count] timing rows to the workspace at args[0].

import 'package:claudart/file_io.dart';
import 'package:claudart/logging/logger.dart';

void main(List<String> args) {
  final logger =
      SessionLogger(io: const RealFileIO(), workspacePath: args[0]);
  for (var i = 0; i < int.parse(args[2]); i++) {
    logger.logPerformance(command: 'w${args[1]}-$i', outcome: 'ok');
  }
}
