// failure_boundary.dart — the one place every error ends up before a command
// exits.
//
// A typed failure ([ClaudartException]) keeps its own [FailureType]. Any other
// error becomes [FailureType.unexpectedFailure], a marker that a type is
// missing, and is logged all the same, so no failure is dropped for lacking a
// type. Both are logged to the error log of the project's workspace, or the
// global one when the project is not known.

import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';
import '../file_io.dart';
import '../git_utils.dart';
import '../logging/logger.dart';
import '../paths.dart';
import '../registry.dart';
import '../sensitivity/token_map.dart';

/// The keys of the context [reportFailure] puts on a failure it had to wrap.
/// The enum name is the key.
enum FailureContextKey {
  /// The message of the untyped error that was wrapped.
  cause,
}

/// Maps [error] to a failure, logs it, and returns it for the caller to print.
///
/// A [ClaudartException] is returned unchanged. Anything else is wrapped as
/// [FailureType.unexpectedFailure] with the original message as its
/// [FailureContextKey.cause], and [stackTrace] is logged with it. The log goes
/// to the workspace of the project at [projectRoot], or at the git root when it
/// is null; when no project is registered there it goes to the global log. In a
/// sensitive project the reason is abstracted with the project's token map.
ClaudartException reportFailure({
  required String command,
  required Object error,
  StackTrace? stackTrace,
  String? projectRoot,
  FileIO? io,
}) {
  final fileIO = io ?? const RealFileIO();
  final failure = error is ClaudartException
      ? error
      : ClaudartException(
          FailureType.unexpectedFailure,
          context: {FailureContextKey.cause.name: error.toString()},
        );

  final root = projectRoot ?? detectGitContext()?.root;
  final entry =
      root == null ? null : Registry.load(io: fileIO).findByProjectRoot(root);
  TokenMap? tokenMap;
  var abstractable = true;
  if (entry != null && entry.sensitivityMode) {
    try {
      tokenMap = TokenMap.load(tokenMapPathFor(entry.workspacePath), io: fileIO);
    } on TokenMapUnreadableException {
      abstractable = false;
    }
  }

  SessionLogger(
    io: fileIO,
    sensitivityMode: entry?.sensitivityMode ?? false,
    tokenMap: tokenMap,
    workspacePath: entry?.workspacePath,
  ).logError(
    command: command,
    errorType: failure.errorType.name,
    fingerprint: '$command.${failure.failureType.name}',
    // A sensitive project whose token map cannot be read cannot abstract the
    // message, so only the failure's own label is written, never the message
    // or the stack trace.
    reason: abstractable ? failure.toString() : failure.failureType.label,
    stackTrace: abstractable && error is! ClaudartException
        ? stackTrace?.toString()
        : null,
  );
  return failure;
}
