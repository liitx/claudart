// mutant_faults.dart — line-level mutants of one source file
//
// The matrices of the earlier providers change one stated fact. This changes
// one line of any file by one well-known operator, so every line of a file is
// asked the same question: does a test fail if this line is wrong? The tests
// that fail are recorded, so the ledger can say which test to update when the
// logic on a line changes, which lines no test guards, and which tests guard
// nothing another does not.
//
// An operator is compile-safe on the shapes it matches (operators anchored on
// spaces, so a generic's `<` is never touched; no change inside a string
// literal). A mutant that still does not compile is `invalid`, never a catch.

import 'dart:io';

import 'fault.dart';
import 'line_faults.dart';

/// A way of changing a line.
class MutationOperator {
  const MutationOperator(this.id, this.pattern, this.change);

  /// Names the operator in the log.
  final String id;
  final String pattern;

  /// The replacement for one match of [pattern] (or null to delete the line).
  final String? Function(Match match) change;
}

/// A statement that is one call and nothing else: removing it removes an effect.
final _callStatement = RegExp(r'^\s+[A-Za-z_][\w.!?]*\(.*\);\s*$');
const _notStatements = ['return', 'throw', 'assert', 'super', 'this', 'await'];

final mutationOperators = <MutationOperator>[
  MutationOperator('equals', r' == ', (_) => ' != '),
  MutationOperator('notEquals', r' != ', (_) => ' == '),
  MutationOperator('and', r' && ', (_) => ' || '),
  MutationOperator('or', r' \|\| ', (_) => ' && '),
  MutationOperator('lessThan', r' < ', (_) => ' <= '),
  MutationOperator('lessOrEqual', r' <= ', (_) => ' < '),
  MutationOperator('greaterThan', r' > ', (_) => ' >= '),
  MutationOperator('greaterOrEqual', r' >= ', (_) => ' > '),
  MutationOperator('true', r'\btrue\b', (_) => 'false'),
  MutationOperator('false', r'\bfalse\b', (_) => 'true'),
  MutationOperator('plus', r'(?<![\x27"]) \+ ', (_) => ' - '),
  MutationOperator('minus', r' - ', (_) => ' + '),
  MutationOperator('negation', r'\(!', (_) => '('),
  MutationOperator('number', r'(?<![\w.$])(\d+)(?![\w.])', (m) => '${int.parse(m.group(1)!) + 1}'),
];

/// Whether [index] of [line] lies inside a string literal.
bool _insideString(String line, int index) {
  var single = false;
  var double = false;
  for (var i = 0; i < index; i++) {
    final char = line[i];
    if (char == r'\') {
      i++;
    } else if (char == "'" && !double) {
      single = !single;
    } else if (char == '"' && !single) {
      double = !double;
    }
  }
  return single || double;
}

/// The index where a trailing `//` comment starts, or the line's length.
int _commentStart(String line) {
  for (var i = 0; i < line.length - 1; i++) {
    if (line[i] == '/' && line[i + 1] == '/' && !_insideString(line, i)) return i;
  }
  return line.length;
}

/// Every mutant of [line] (1-based [number]) as (id, new text) pairs; a null
/// text deletes the line. [previous] is the line above: a call is removed only
/// where it starts a statement, not where it ends an expression body.
List<(String, String?)> mutantsOfLine(String line, int number, {String previous = ''}) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ') ||
      trimmed.startsWith('part ') ||
      trimmed.startsWith('@')) {
    return const [];
  }
  final commentAt = _commentStart(line);
  final mutants = <(String, String?)>[];
  for (final operator in mutationOperators) {
    var occurrence = 0;
    for (final match in RegExp(operator.pattern).allMatches(line)) {
      if (_insideString(line, match.start) || match.start >= commentAt) continue;
      occurrence++;
      final replacement = operator.change(match);
      mutants.add((
        '${operator.id}${occurrence > 1 ? '#$occurrence' : ''}',
        line.replaceRange(match.start, match.end, replacement!),
      ));
    }
  }
  final above = previous.trimRight();
  final startsStatement = above.isEmpty ||
      above.endsWith(';') ||
      above.endsWith('{') ||
      above.endsWith('}');
  if (_callStatement.hasMatch(line) &&
      startsStatement &&
      !_notStatements.any((word) => trimmed.startsWith(word))) {
    mutants.add(('deleteStatement', null));
  }
  return mutants;
}

/// Mutants of [file], checked by [tierOne] then [tierTwo].
class FileMutantFaults extends FaultProvider {
  const FileMutantFaults({
    required this.file,
    required this.tierOne,
    required this.tierTwo,
  });

  /// The source file, relative to the repository root.
  final String file;
  final List<String> tierOne;
  final List<String> tierTwo;

  @override
  String get proof => 'mutants:$file';

  @override
  List<String> get tierOneTests => tierOne;

  @override
  List<String> get tierTwoTests => tierTwo;

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$file').readAsStringSync().split('\n');
    final faults = <SeededFault>[];
    for (var index = 0; index < lines.length; index++) {
      final number = index + 1;
      final previous = index == 0 ? '' : lines[index - 1];
      for (final (id, text) in mutantsOfLine(lines[index], number, previous: previous)) {
        faults.add(LineEditFault(
          proof: proof,
          description: 'line $number $id: `${lines[index].trim()}` -> '
              '${text == null ? 'removed' : '`${text.trim()}`'}',
          sourceFile: file,
          sourceLine: number,
          edit: (all) => text == null
              ? [...all.sublist(0, number - 1), '', ...all.sublist(number)]
              : replacingLine(all, number, text),
        ));
      }
    }
    return faults;
  }
}
