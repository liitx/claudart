// handoff_consistency.dart — how many saved handoffs disagree with themselves.
//
// Reads every `.md` file in the directories given, parses each as a handoff,
// and counts the findings (a status that is ahead of its content, or content
// that is ahead of its status). Read only.
//
//   dart run tool/refactor_audit/handoff_consistency.dart <dir> [<dir> ...]
//   make handoff-consistency DIR=<archive directory>

import 'dart:io';

import 'package:claudart/session/handoff_finding.dart';
import 'package:claudart/session/session_state.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: handoff_consistency.dart <dir> [<dir> ...]');
    exit(2);
  }
  var total = 0;
  var consistent = 0;
  final byFinding = {for (final finding in HandoffFinding.values) finding: 0};
  for (final dir in args) {
    for (final entity in Directory(dir).listSync()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final findings =
          SessionState.parse(entity.readAsStringSync()).findings;
      total++;
      if (findings.isEmpty) consistent++;
      for (final finding in findings) {
        byFinding[finding] = byFinding[finding]! + 1;
      }
    }
  }
  stdout.writeln('handoffs read: $total');
  stdout.writeln('consistent: $consistent');
  for (final entry in byFinding.entries) {
    stdout.writeln('${entry.key.name}: ${entry.value}');
  }
}
