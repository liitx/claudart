// line_faults.dart — a fault that edits lines of one source file
//
// For a matrix whose facts are written as data in the source (an enum's
// constructor arguments, the arms of a switch), a fault is one edit of one
// fact: a value flipped, an arm retargeted, an element added or removed. The
// edit is a function from the file's lines to its new lines, and the fault
// records the line it stands for, so a missed fault points at that line.

import 'fault.dart';

/// One edit of [sourceFile] standing for [sourceLine].
class LineEditFault extends SeededFault {
  const LineEditFault({
    required this.proof,
    required this.description,
    required this.sourceFile,
    required this.sourceLine,
    required this.edit,
  });

  @override
  final String proof;

  @override
  final String description;

  @override
  final String sourceFile;

  @override
  final int sourceLine;

  /// The file's lines with the fault in place.
  final List<String> Function(List<String> lines) edit;

  @override
  String apply(String source) => edit(source.split('\n')).join('\n');
}

/// [lines] with line [number] (1-based) replaced by [text].
List<String> replacingLine(List<String> lines, int number, String text) => [
      ...lines.sublist(0, number - 1),
      text,
      ...lines.sublist(number),
    ];

/// The 1-based line numbers of [lines] from [from] on, up to and including the
/// first line equal to [until]. Fails when [until] is not found, so a provider
/// cannot silently scan nothing.
List<int> linesBetween(List<String> lines, int from, String until) {
  final numbers = <int>[];
  for (var index = from - 1; index < lines.length; index++) {
    numbers.add(index + 1);
    if (lines[index] == until) return numbers;
  }
  throw StateError('no line equal to "$until" after line $from');
}
