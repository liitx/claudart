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
import '../registry.dart';

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
  RegistryEntry? entry;
  var registryReadable = true;
  if (root != null) {
    try {
      entry = Registry.load(io: fileIO).findByProjectRoot(root);
    } on CorruptRegistryException {
      registryReadable = false;
    }
  }
  // An unreadable registry cannot say whether the project is sensitive, so no
  // text is logged rather than guessing it is not.
  final logger = !registryReadable
      ? SessionLogger.labelOnly(io: fileIO)
      : entry == null
          ? SessionLogger.plain(io: fileIO)
          : SessionLogger.forEntry(entry, io: fileIO);
  logger.logError(
    command: command,
    errorType: failure.errorType.name,
    fingerprint: '$command.${failure.failureType.name}',
    reason: failure.toString(),
    stackTrace: error is ClaudartException ? null : stackTrace?.toString(),
  );
  return failure;
}
