// append_log_lines.dart — a child process for the concurrent-writer test:
// logs [count] interactions to the workspace at args[0], as writer args[1].
//
// A separate process, not an isolate: Dart's file lock is per process, so
// isolates in one process would not exercise what two claudart commands do.

import 'package:claudart/file_io.dart';
import 'package:claudart/logging/logger.dart';

void main(List<String> args) {
  final workspace = args[0];
  final writer = args[1];
  final count = int.parse(args[2]);
  final logger =
      SessionLogger(io: const RealFileIO(), workspacePath: workspace);
  for (var i = 0; i < count; i++) {
    logger.logInteraction(command: 'w$writer-$i', outcome: 'ok');
  }
}
