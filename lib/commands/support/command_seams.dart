// command_seams.dart — the injected seams every command shares, as one value
//
// A command reaches the file system, the process exit, the user's yes/no and
// menu pick, and the project root through these. Passing them as one bundle
// stops every command from redeclaring the same five parameters.

import '../../io/file_io.dart';

/// The seams a command can have replaced. Every field is optional: a command
/// that is given none uses the real file system, the real exit and the real
/// terminal prompts.
class CommandSeams {
  const CommandSeams({
    this.io,
    this.projectRootOverride,
    this.exitFn,
    this.confirmFn,
    this.askFn,
    this.pickFn,
    this.clock,
  });

  /// The file system the command reads and writes.
  final FileIO? io;

  /// The project root to act on instead of the one found from git.
  final String? projectRootOverride;

  /// How the command leaves the process with a code.
  final Never Function(int code)? exitFn;

  /// A yes/no answer to a question, for commands that cannot reach end of
  /// input.
  final bool Function(String question)? confirmFn;

  /// A yes/no/end-of-input answer to a question.
  final bool? Function(String question)? askFn;

  /// Which item of a menu the user picked.
  final int Function(List<String> items)? pickFn;

  /// The time the command reads, instead of the wall clock.
  final DateTime Function()? clock;

  /// The same seams, acting on another project.
  CommandSeams forProjectRoot(String projectRoot) => CommandSeams(
        io: io,
        projectRootOverride: projectRoot,
        exitFn: exitFn,
        confirmFn: confirmFn,
        askFn: askFn,
        pickFn: pickFn,
        clock: clock,
      );
}
