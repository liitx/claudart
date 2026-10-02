// check_coverage.dart — line-coverage floor check against coverage/lcov.info
//
// Sums LF:/LH: (lines found/lines hit) across every file in the tracefile
// and compares against a threshold — no dependency on the `lcov` system
// package, the format is simple enough to parse directly. Usage:
//   dart run tool/check_coverage.dart <min_percent>

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/check_coverage.dart <min_percent>');
    exit(2);
  }
  final minPercent = double.parse(args.first);

  final tracefile = File('coverage/lcov.info');
  if (!tracefile.existsSync()) {
    stderr.writeln('coverage/lcov.info not found — run `make test-coverage` first.');
    exit(2);
  }

  var linesFound = 0;
  var linesHit = 0;
  for (final line in tracefile.readAsLinesSync()) {
    if (line.startsWith('LF:')) linesFound += int.parse(line.substring(3));
    if (line.startsWith('LH:')) linesHit += int.parse(line.substring(3));
  }

  if (linesFound == 0) {
    stderr.writeln('No coverage data found in coverage/lcov.info.');
    exit(2);
  }

  final percent = linesHit / linesFound * 100;
  final formatted = percent.toStringAsFixed(1);
  if (percent < minPercent) {
    stderr.writeln(
        'Line coverage $formatted% is below the $minPercent% floor ($linesHit/$linesFound lines).');
    exit(1);
  }
  print('Line coverage $formatted% meets the $minPercent% floor ($linesHit/$linesFound lines).');
}
