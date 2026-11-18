// closure_faults.dart — single changes to the closure-evidence matrix
//
// `closureEvidenceOf` says what a converged handoff rests on and
// `automaticClosureFor` says what an automatic close does about it. Together
// they decide which handoffs a headless run archives, so each fact is changed
// on its own: every evidence value a branch returns becomes each other value,
// every action an arm names becomes each other action, and each guard
// comparison is flipped.

import 'dart:io';

import 'package:claudart/session/closure_evidence.dart';

import 'fault.dart';
import 'line_faults.dart';

const _sourceFilePath = 'lib/session/closure_evidence.dart';
const _evidenceSignature = 'ClosureEvidence closureEvidenceOf(SessionState state) {';
const _closureSignature = 'AutomaticClosure automaticClosureFor(ClosureEvidence evidence) =>';

class ClosureEvidenceFaults extends FaultProvider {
  const ClosureEvidenceFaults();

  @override
  String get proof => 'closureEvidence';

  @override
  List<String> get coveredTables => const ['closureEvidenceOf', 'automaticClosureFor'];

  @override
  List<String> get tierOneTests => const [
        'test/session/closure_evidence_test.dart',
        'test/commands/teardown_test.dart',
      ];

  @override
  List<String> get tierTwoTests => const [
        'test/session',
        'test/commands',
        'test/conformance',
        'test/topology',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = _readLines(repositoryRoot, _sourceFilePath);
    final faults = <SeededFault>[];

    final evidenceStart = lines.indexOf(_evidenceSignature) + 1;
    for (final number in linesBetween(lines, evidenceStart, '}')) {
      final line = lines[number - 1];
      for (final match in RegExp(r'ClosureEvidence\.(\w+)').allMatches(line)) {
        for (final other in ClosureEvidence.values) {
          if (other.name == match.group(1)) continue;
          faults.add(_edit(
            number,
            'closureEvidenceOf returns ${other.name} where it returned '
            '${match.group(1)}',
            (lines) => replacingLine(
              lines,
              number,
              line.replaceRange(match.start, match.end, 'ClosureEvidence.${other.name}'),
            ),
          ));
        }
      }
      if (RegExp(r'\s!=(\s|$)').hasMatch(line)) {
        faults.add(_edit(
          number,
          'closureEvidenceOf guard compares with == where it used !=',
          (lines) => replacingLine(lines, number, line.replaceFirst('!=', '==')),
        ));
      }
    }

    final closureStart = lines.indexOf(_closureSignature) + 1;
    for (final number in linesBetween(lines, closureStart, '    };')) {
      final line = lines[number - 1];
      final match = RegExp(r'=> AutomaticClosure\.(\w+),').firstMatch(line);
      if (match == null) continue;
      for (final other in AutomaticClosure.values) {
        if (other.name == match.group(1)) continue;
        faults.add(_edit(
          number,
          'automaticClosureFor does ${other.name} where it did ${match.group(1)}',
          (lines) => replacingLine(
            lines,
            number,
            line.replaceFirst(
              'AutomaticClosure.${match.group(1)}',
              'AutomaticClosure.${other.name}',
            ),
          ),
        ));
      }
    }
    return faults;
  }

  LineEditFault _edit(
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

List<String> _readLines(String root, String path) =>
    File('$root/$path').readAsStringSync().split('\n');
