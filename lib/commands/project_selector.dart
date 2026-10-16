// project_selector.dart — `--project <name>`: choose which linked workspace a
// command acts on, instead of whatever the current directory happens to be.
//
// Commands resolve their project from the current directory's git root. That is
// right inside a project's own repo and wrong anywhere else (an agent that has
// moved into another checkout, or one coordinating several workspaces). The
// selector resolves a registered NAME to its project root once, in bin/, and
// hands it to the command as its existing project override. Only registered
// names resolve: never an arbitrary path.

import 'dart:io';

import '../file_io.dart';
import '../logging/logger.dart';
import '../registry.dart';
import 'workspaces.dart' show WorkspaceInteraction;

/// The `--project` option's own strings.
abstract final class ProjectOption {
  static const flag = '--project';
  static const anyOptionPrefix = '--';
  static const valueSeparator = '=';
}

/// Records, in the selected workspace's own interactions.jsonl, that [command]
/// was aimed at it with `--project`. Written to the target, never the caller's
/// workspace, so each workspace's log shows what acted on it.
void logProjectTargeted(
  RegistryEntry entry,
  String command, {
  FileIO? io,
}) {
  SessionLogger(
    io: io,
    sensitivityMode: entry.sensitivityMode,
    workspacePath: entry.workspacePath,
  ).logInteraction(
    command: command,
    outcome: WorkspaceInteraction.projectTargeted.outcomeFor(),
    platform: Platform.operatingSystem,
  );
}

/// [args] with `--project NAME` / `--project=NAME` removed, the name, and
/// whether the option was given without a usable value.
({List<String> args, String? name, bool missingValue}) extractProjectOption(
  List<String> args,
) {
  final keptArgs = <String>[];
  String? projectName;
  var isMissingValue = false;
  const flagWithValue = '${ProjectOption.flag}${ProjectOption.valueSeparator}';
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == ProjectOption.flag) {
      final next = index + 1 < args.length ? args[index + 1] : null;
      if (next == null || next.startsWith(ProjectOption.anyOptionPrefix)) {
        isMissingValue = true;
      } else {
        projectName = next;
        index++;
      }
    } else if (arg.startsWith(flagWithValue)) {
      final value = arg.substring(flagWithValue.length);
      if (value.isEmpty) {
        isMissingValue = true;
      } else {
        projectName = value;
      }
    } else {
      keptArgs.add(arg);
    }
  }
  return (args: keptArgs, name: projectName, missingValue: isMissingValue);
}

sealed class ProjectSelection {
  const ProjectSelection();
}

/// No `--project` was given: use the current directory, as always.
class NoProjectSelected extends ProjectSelection {
  const NoProjectSelected();
}

class ProjectSelected extends ProjectSelection {
  const ProjectSelected(this.entry);

  final RegistryEntry entry;
}

class ProjectNotFound extends ProjectSelection {
  const ProjectNotFound(this.name, this.known);

  final String name;

  /// The linked workspaces' names, sorted.
  final List<String> known;

  String get message => known.isEmpty
      ? "Unknown project '$name'. No workspaces are linked; run "
          '`claudart link` in a project first.'
      : "Unknown project '$name'. Linked workspaces: ${known.join(', ')}. "
          'Run `claudart workspaces` to see them.';
}

/// Resolves [name] against [registry]. Exact name match only.
ProjectSelection selectProject(Registry registry, String? name) {
  if (name == null) return const NoProjectSelected();
  final entry = registry.findByName(name);
  if (entry != null) return ProjectSelected(entry);
  final known = [for (final entry in registry.entries) entry.name]..sort();
  return ProjectNotFound(name, known);
}
