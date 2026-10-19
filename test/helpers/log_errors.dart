// log_errors.dart — a child process for the concurrent logError test: logs
// [count] errors to the workspace at args[0]. Errors with the same
// fingerprint are one deduplicated entry with a count, which is the
// read-modify-write that must not lose updates.
//
// args: <workspace> <writer> <count> <shared|distinct>

import 'package:claudart/file_io.dart';
import 'package:claudart/logging/logger.dart';

void main(List<String> args) {
  final workspace = args[0];
  final writer = args[1];
  final count = int.parse(args[2]);
  final shared = args[3] == 'shared';
  final logger =
      SessionLogger(io: const RealFileIO(), workspacePath: workspace);
  for (var i = 0; i < count; i++) {
    logger.logError(
      command: 'w$writer',
      errorType: 'test',
      fingerprint: shared ? 'shared.fp' : 'w$writer.$i',
      reason: 'boom',
    );
  }
}
