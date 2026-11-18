// project_logger_faults.dart — single changes to the choice of a command's logger
//
// `loggerForProject` decides where a record goes and how its text is protected,
// by project root, registry and sensitivity. The line mutants of that function
// cannot be judged (flipping a null check breaks the promotion the next line
// relies on, so they do not compile), so each choice is changed on its own here:
// every logger it builds becomes each other kind, and the root it asks about
// loses its explicit root, or its git fallback.

import 'dart:io';

import 'fault.dart';
import 'line_faults.dart';

const _sourceFilePath = 'lib/commands/support/project_logger.dart';
const _signature = 'SessionLogger loggerForProject({';
const _loggerCall = r'SessionLogger\.(plain|labelOnly|forEntry)\(([^)]*)\)';
const _kinds = {
  'plain': 'SessionLogger.plain(io: fileIO)',
  'labelOnly': 'SessionLogger.labelOnly(io: fileIO)',
};
const _rootLine = 'final root = projectRoot ?? detectGitContext(runner: runner)?.root;';

class ProjectLoggerFaults extends FaultProvider {
  const ProjectLoggerFaults();

  @override
  String get proof => 'projectLogger';

  @override
  List<String> get tierOneTests =>
      const ['test/commands/support/project_logger_test.dart'];

  @override
  List<String> get tierTwoTests => const [
        'test/commands',
        'test/logging',
        'test/topology',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$_sourceFilePath').readAsStringSync().split('\n');
    final start = lines.indexWhere((l) => l.contains(_signature)) + 1;
    final faults = <SeededFault>[];
    for (var number = start + 1; number <= lines.length; number++) {
      final line = lines[number - 1];
      if (line == '}') break;
      for (final match in RegExp(_loggerCall).allMatches(line)) {
        for (final kind in _kinds.entries) {
          if (kind.key == match.group(1)) continue;
          faults.add(_fault(
            number,
            'a ${match.group(1)} logger becomes a ${kind.key} logger',
            (lines) => replacingLine(
              lines,
              number,
              line.replaceRange(match.start, match.end, kind.value),
            ),
          ));
        }
      }
      if (line.trim() == _rootLine) {
        faults.add(_fault(
          number,
          'the root ignores the git fallback',
          (lines) => replacingLine(
              lines, number, line.replaceFirst('projectRoot ?? detectGitContext(runner: runner)?.root', 'projectRoot')),
        ));
        faults.add(_fault(
          number,
          'the root ignores the explicit project root',
          (lines) => replacingLine(
              lines, number, line.replaceFirst('projectRoot ?? detectGitContext(runner: runner)?.root', 'detectGitContext(runner: runner)?.root')),
        ));
      }
    }
    return faults;
  }

  LineEditFault _fault(
    int line,
    String description,
    List<String> Function(List<String> lines) edit,
  ) =>
      LineEditFault(
        proof: proof,
        description: 'line $line: $description',
        sourceFile: _sourceFilePath,
        sourceLine: line,
        edit: edit,
      );
}
