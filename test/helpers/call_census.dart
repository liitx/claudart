// call_census.dart — which kind of file a call touched, and how often.
//
// Every path is classified into exactly one [CensusFile]. The kinds are
// named by the file-name constants in lib/config/paths.dart, never respelled here;
// a path that is none of the named kinds is `other`, the complement, so a
// file nobody has named yet still shows up in the count.

import 'package:claudart/config/paths.dart';
import 'package:path/path.dart' as p;

import 'counting_file_io.dart';

/// The kinds of file a command touches, in the order the census prints them.
enum CensusFile {
  registry(registryFileName),
  handoff(handoffFileName),
  workspaceConfig(workspaceConfigFileName),
  config(configFileName),
  skills(skillsFileName),
  pendingConfirmation(pendingConfirmationFileName),
  log(null),
  other(null);

  const CensusFile(this.fileName);

  /// The exact file name that makes a path this kind; null for the kinds
  /// decided another way.
  final String? fileName;

  /// The kind of [path]: a named file by its name, a log by its directory,
  /// otherwise [other].
  static CensusFile of(String path) {
    if (p.basename(p.dirname(path)) == p.basename(logsDirFor(''))) return log;
    for (final kind in values) {
      if (kind.fileName == p.basename(path)) return kind;
    }
    return other;
  }
}

/// Calls of [operation] on files of kind [file] in [calls].
int countCalls(
  List<FileCall> calls,
  CensusFile file,
  FileOperation operation,
) =>
    calls
        .where(
          (call) =>
              call.operation == operation && CensusFile.of(call.path) == file,
        )
        .length;
