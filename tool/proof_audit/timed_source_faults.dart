// timed_source_faults.dart — single changes to the timed-source matrix
//
// `TimedSource.logFile` says which log holds each source's rows, so a wrong arm
// makes the reader look at the wrong log and report nothing, or someone else's
// durations. Each arm's log is changed to every other log, one at a time.

import 'dart:io';

import 'package:claudart/logging/log_file.dart';

import 'fault.dart';
import 'line_faults.dart';

const _sourceFilePath = 'lib/logging/timed_source.dart';
const _signature = '  LogFile get logFile => switch (this) {';

class TimedSourceFaults extends FaultProvider {
  const TimedSourceFaults();

  @override
  String get proof => 'timedSource';

  @override
  List<String> get coveredTables => const ['logFile'];

  @override
  List<String> get tierOneTests => const ['test/logging/timed_source_test.dart'];

  @override
  List<String> get tierTwoTests => const [
        'test/logging',
        'test/commands',
        'test/topology',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$_sourceFilePath').readAsStringSync().split('\n');
    final start = lines.indexOf(_signature) + 1;
    final faults = <SeededFault>[];
    for (final number in linesBetween(lines, start, '      };')) {
      final line = lines[number - 1];
      final match = RegExp(r'=> LogFile\.(\w+),').firstMatch(line);
      if (match == null) continue;
      for (final other in LogFile.values) {
        if (other.name == match.group(1)) continue;
        faults.add(LineEditFault(
          proof: proof,
          description: 'line $number: logFile names ${other.name} where it named '
              '${match.group(1)}',
          sourceFile: _sourceFilePath,
          sourceLine: number,
          edit: (lines) => replacingLine(
            lines,
            number,
            line.replaceFirst('LogFile.${match.group(1)}', 'LogFile.${other.name}'),
          ),
        ));
      }
    }
    return faults;
  }
}
