// check_coverage.dart — line-coverage floors against coverage/lcov.info
//
// Reads the tracefile directly (no dependency on the `lcov` system package,
// the format is simple enough) and checks two kinds of floor:
//   - the repo-wide one: lines hit over lines found, across every file;
//   - per-directory ones, for the logic layers, where a dropped line is a
//     dropped test and not an untestable terminal or process call.
// Usage:
//   dart run tool/check_coverage.dart <min_percent> [<dir>=<min_percent> ...]
//   e.g. dart run tool/check_coverage.dart 84.0 lib/session=93.0

import 'dart:io';

/// Lines found and hit, summed.
typedef LineCount = ({int found, int hit});

const _sourceFile = 'SF:';
const _linesFound = 'LF:';
const _linesHit = 'LH:';
const _floorSeparator = '=';

double percentOf(LineCount count) =>
    count.found == 0 ? 100 : count.hit / count.found * 100;

/// Per-file line counts from an lcov tracefile's text, keyed by the path as
/// written after `SF:`.
Map<String, LineCount> countsByFile(String tracefile) {
  final counts = <String, LineCount>{};
  String? file;
  var found = 0;
  for (final line in tracefile.split('\n')) {
    if (line.startsWith(_sourceFile)) {
      file = line.substring(_sourceFile.length);
    } else if (line.startsWith(_linesFound)) {
      found = int.parse(line.substring(_linesFound.length));
    } else if (line.startsWith(_linesHit) && file != null) {
      counts[file] = (
        found: found,
        hit: int.parse(line.substring(_linesHit.length)),
      );
    }
  }
  return counts;
}

LineCount sum(Iterable<LineCount> counts) => (
      found: counts.fold(0, (total, c) => total + c.found),
      hit: counts.fold(0, (total, c) => total + c.hit),
    );

/// The files under [directory] (a path like `lib/session`), matched as a
/// path segment sequence anywhere in the traced path, so absolute and
/// relative tracefiles both work and `lib/ui` does not match `lib/ui_extra`.
LineCount countUnder(String directory, Map<String, LineCount> byFile) {
  final needle = '/${directory.replaceAll(RegExp(r'^/|/$'), '')}/';
  return sum([
    for (final entry in byFile.entries)
      if ('/${entry.key}'.contains(needle)) entry.value,
  ]);
}

/// Parses `dir=percent` arguments.
Map<String, double> parseDirectoryFloors(Iterable<String> args) => {
      for (final arg in args)
        arg.substring(0, arg.indexOf(_floorSeparator)):
            double.parse(arg.substring(arg.indexOf(_floorSeparator) + 1)),
    };

/// One line per floor that is not met; empty when every floor holds. A
/// directory with no traced lines is itself a failure: a typo or a moved
/// directory must not turn a floor into a silent pass.
List<String> failures({
  required Map<String, LineCount> byFile,
  required double repoFloor,
  required Map<String, double> directoryFloors,
}) {
  final problems = <String>[];
  final total = sum(byFile.values);
  if (percentOf(total) < repoFloor) {
    problems.add(
      'Line coverage ${percentOf(total).toStringAsFixed(1)}% is below the '
      '$repoFloor% floor (${total.hit}/${total.found} lines).',
    );
  }
  directoryFloors.forEach((directory, floor) {
    final count = countUnder(directory, byFile);
    if (count.found == 0) {
      problems.add('$directory has no traced lines: check the directory name.');
    } else if (percentOf(count) < floor) {
      problems.add(
        '$directory: ${percentOf(count).toStringAsFixed(1)}% is below its '
        '$floor% floor (${count.hit}/${count.found} lines).',
      );
    }
  });
  return problems;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_coverage.dart <min_percent> '
      '[<dir>=<min_percent> ...]',
    );
    exit(2);
  }
  final repoFloor = double.parse(args.first);
  final directoryFloors = parseDirectoryFloors(args.skip(1));

  final tracefile = File('coverage/lcov.info');
  if (!tracefile.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info not found — run `make test-coverage` first.',
    );
    exit(2);
  }
  final byFile = countsByFile(tracefile.readAsStringSync());
  final total = sum(byFile.values);
  if (total.found == 0) {
    stderr.writeln('No coverage data found in coverage/lcov.info.');
    exit(2);
  }

  final problems = failures(
    byFile: byFile,
    repoFloor: repoFloor,
    directoryFloors: directoryFloors,
  );
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  print(
    'Line coverage ${percentOf(total).toStringAsFixed(1)}% meets the '
    '$repoFloor% floor (${total.hit}/${total.found} lines).',
  );
  directoryFloors.forEach((directory, floor) {
    final count = countUnder(directory, byFile);
    print(
      '  $directory ${percentOf(count).toStringAsFixed(1)}% meets its '
      '$floor% floor (${count.hit}/${count.found} lines).',
    );
  });
}
