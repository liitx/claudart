// project_resolution.dart — finding the project a command acts on
//
// Every command that works on one project starts the same way: take the
// project root (the override, else git's), load the registry, find the entry.
// That is written here once; a command that cannot proceed gets the same
// words and the same exit.


import '../../generated/user_text.g.dart';
import '../../io/file_io.dart';
import '../../io/git_utils.dart';
import '../../io/process_runner.dart';
import '../../registry.dart';
import 'command_seams.dart';
import '../../io/process_exit.dart';

/// Why a project could not be found, and what the user is told.
enum ProjectLookupFailure {
  notInGitRepository(texts: [UserText.notInGitRepository]),
  notRegistered(
    texts: [
      UserText.projectNotRegisteredHeadline,
      UserText.projectNotRegisteredHint,
    ],
  );

  const ProjectLookupFailure({required this.texts});

  /// What the user is told, one line each.
  final List<UserText> texts;

  List<String> get lines => [for (final text in texts) text.template];
}

/// Tells the user which project the command is acting on.
void printProjectLine(RegistryEntry entry) =>
    print(UserText.projectLine.format({'name': entry.name}));

/// A project found in the registry.
class ResolvedProject {
  const ResolvedProject({
    required this.projectRoot,
    required this.registry,
    required this.entry,
    required this.gitContext,
  });

  final String projectRoot;
  final Registry registry;
  final RegistryEntry entry;

  /// Git's view of the working directory; read only when asked for.
  final GitContext? gitContext;
}

/// The project a command acts on, or why there is none.
///
/// [withGitContext] reads git's branch and root for [projectRootOverride] (or
/// the working directory); without it git is asked only when there is no
/// override.
ResolvedProject? lookupProject(
  CommandSeams seams, {
  bool withGitContext = false,
  ProcessRunner? runner,
  void Function(ProjectLookupFailure failure)? onFailure,
}) {
  final io = seams.io ?? const RealFileIO();
  final projectRootOverride = seams.projectRootOverride;
  final gitContext = withGitContext
      ? detectGitContext(runner: runner, workingDirectory: projectRootOverride)
      : null;
  final projectRoot = projectRootOverride ??
      (withGitContext ? gitContext?.root : detectGitContext(runner: runner)?.root);
  if (projectRoot == null) {
    onFailure?.call(ProjectLookupFailure.notInGitRepository);
    return null;
  }
  final registry = Registry.load(io: io);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    onFailure?.call(ProjectLookupFailure.notRegistered);
    return null;
  }
  return ResolvedProject(
    projectRoot: projectRoot,
    registry: registry,
    entry: entry,
    gitContext: gitContext,
  );
}

/// The project a command acts on. When there is none the user is told why and
/// the process exits with 1.
ResolvedProject requireProject(
  CommandSeams seams, {
  bool withGitContext = false,
}) {
  ProjectLookupFailure? failure;
  final project = lookupProject(
    seams,
    withGitContext: withGitContext,
    onFailure: (found) => failure = found,
  );
  if (project != null) return project;
  for (final line in failure!.lines) {
    print(line);
  }
  noteExitReason(failure!);
  (seams.exitFn ?? exitProcess)(1);
}
