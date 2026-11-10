// ledger.dart — which test guards which line, and which lines nothing guards
//
// Built from the mutant rows of `proofs.jsonl` (see mutant_faults.dart) and,
// when given, a line-coverage tracefile. For each source file it says how its
// mutants ended, and from that:
//
//   * the impact map: for a line, the tests that fail when it is wrong, so a
//     change to that line names the tests to update and none needs adding;
//   * survivors: a line no test guards, with the existing tests that guard its
//     neighbors in the same declaration, so the missing assertion goes there;
//   * tests that kill exactly the same mutants, which cannot be told apart by
//     anything the file does and are candidates to merge or to link.
//
// A mutant is `caught` at tier 1 by the file's mirrored test, at tier 2 by the
// wider suite only (the mirrored test is weak or missing), or survives.

import 'package:claudart/logging/logger.dart';

import 'mirror.dart';

/// One mutant row, read from the log.
typedef MutantRow = ({
  String file,
  int line,
  String description,
  ProofVerdict verdict,
  int tier,
  List<String> caughtBy,
});

const mutantProofPrefix = 'mutants:';

/// The mutant rows in [rows], the latest row for each mutant.
List<MutantRow> mutantRows(List<Map<String, dynamic>> rows) {
  final latest = <String, MutantRow>{};
  for (final row in rows) {
    final proof = row[LogEntryField.proof.name] as String;
    if (!proof.startsWith(mutantProofPrefix)) continue;
    final description = row[LogEntryField.fault.name] as String;
    latest['$proof|$description'] = (
      file: proof.substring(mutantProofPrefix.length),
      line: row[LogEntryField.sourceLine.name] as int,
      description: description,
      verdict: ProofVerdict.values.byName(row[LogEntryField.verdict.name] as String),
      tier: row[LogEntryField.tier.name] as int,
      caughtBy: (row[LogEntryField.caughtBy.name] as List<dynamic>).cast<String>(),
    );
  }
  return latest.values.toList();
}

/// Words that open a statement, so a line starting with one is not a declaration.
const _statementKeywords = {
  'if', 'for', 'while', 'switch', 'return', 'else', 'catch', 'try', 'do', 'throw',
  'await', 'assert', 'case', 'default', 'break', 'continue',
};

/// The name of the declaration [line] (1-based) of [lines] sits in: the nearest
/// line above it that opens a member or a top-level declaration.
String enclosingDeclaration(List<String> lines, int line) {
  final opener = RegExp(
    r'^(?:  )?(?:static\s+|abstract\s+|final\s+|const\s+)*(?:[\w<>?,\[\]]+\s+)*(?:get\s+)?([\w.]+)\s*(?:\(|=>|\{)',
  );
  for (var index = line - 1; index >= 0; index--) {
    final text = lines[index];
    final indent = text.length - text.trimLeft().length;
    if (indent > 2 || text.trim().isEmpty || text.trimLeft().startsWith('//')) continue;
    if (text.trimLeft().startsWith('}') || text.trimLeft().startsWith(')')) continue;
    final match = opener.firstMatch(text);
    if (match != null && !_statementKeywords.contains(match.group(1))) {
      return match.group(1)!;
    }
    if (RegExp(r'^\s*(class|enum|extension|mixin)\s+(\w+)').firstMatch(text)
        case final declaration?) {
      return declaration.group(2)!;
    }
  }
  return '(top of file)';
}

/// Hit counts by line from an lcov tracefile, for each file it names (paths as
/// `lib/...`, found by their last `lib/` segment).
Map<String, Map<int, int>> lineHits(String lcov) {
  final hits = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final line in lcov.split('\n')) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3);
      final at = path.lastIndexOf('lib/');
      current = hits.putIfAbsent(at < 0 ? path : path.substring(at), () => {});
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      current[int.parse(parts[0])] = int.parse(parts[1]);
    }
  }
  return hits;
}

/// Tests grouped by the exact set of mutants they kill, for the groups of at
/// least two tests killing at least [minimumKills] mutants.
List<({List<String> tests, int kills})> identicalKillers(
  List<MutantRow> rows, {
  int minimumKills = 3,
}) {
  final kills = <String, Set<String>>{};
  for (final row in rows) {
    for (final test in row.caughtBy) {
      (kills[test] ??= {}).add('${row.file}|${row.description}');
    }
  }
  final byKills = <String, List<String>>{};
  kills.forEach((test, set) {
    final key = (set.toList()..sort()).join('\n');
    (byKills[key] ??= []).add(test);
  });
  return [
    for (final entry in byKills.entries)
      if (entry.value.length > 1 && entry.key.split('\n').length >= minimumKills)
        (tests: entry.value..sort(), kills: entry.key.split('\n').length),
  ]..sort((a, b) => b.kills.compareTo(a.kills));
}

/// The tests that must be looked at when [line] of [file] changes: those that
/// failed for a mutant of that line.
List<String> testsGuarding(List<MutantRow> rows, String file, int line) => {
      for (final row in rows)
        if (row.file == file && row.line == line) ...row.caughtBy,
    }.toList()
      ..sort();

/// The markdown ledger. [sources] holds each file's text, [lcov] the line hits
/// (empty when none was measured) and [root] finds the mirrored tests.
String renderLedger({
  required List<MutantRow> rows,
  required Map<String, String> sources,
  required Map<String, Map<int, int>> lcov,
  required String root,
  required String title,
  List<String> excludedTests = const [],
}) {
  final byFile = <String, List<MutantRow>>{};
  final excludedNote = excludedTests.isEmpty
      ? ''
      : '\n\nLeft out of the wider run because they fail on a change that alters '
          'no behavior (they read source text, so they prove nothing about what '
          'the program does): ${excludedTests.map((t) => '`$t`').join(', ')}.';
  for (final row in rows) {
    (byFile[row.file] ??= []).add(row);
  }
  final out = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('> Generated by `dart run tool/proof_audit/run.dart --mutants=... ` '
        'and `ledger.dart` from the mutant rows of `proofs.jsonl`. A mutant is '
        'caught at tier 1 by the file\'s mirrored test, at tier 2 only by the '
        'rest of the suite (the mirrored test is weak or missing), or it '
        'survives: no test guards that line.$excludedNote')
    ..writeln()
    ..writeln('| File | Mirrored test | Mutants | Caught by the mirror | Caught only by the wider suite | Survived | Invalid | Lines run by the suite |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  final files = byFile.keys.toList()..sort();
  for (final file in files) {
    final fileRows = byFile[file]!;
    int count(ProofVerdict verdict, {int? tier}) => fileRows
        .where((r) => r.verdict == verdict && (tier == null || r.tier == tier))
        .length;
    final hits = lcov[file];
    final coverage = hits == null || hits.isEmpty
        ? '—'
        : '${hits.values.where((h) => h > 0).length}/${hits.length}';
    out.writeln('| `$file` | ${mirroredTest(root, file) ?? 'none'} | ${fileRows.length} | '
        '${count(ProofVerdict.caught, tier: 1)} | ${count(ProofVerdict.caught, tier: 2)} | '
        '${count(ProofVerdict.missed)} | ${count(ProofVerdict.invalid)} | $coverage |');
  }

  out
    ..writeln()
    ..writeln('## Lines no test guards')
    ..writeln();
  var anySurvivor = false;
  for (final file in files) {
    final lines = (sources[file] ?? '').split('\n');
    final guardsByDeclaration = <String, Map<String, int>>{};
    for (final row in byFile[file]!) {
      if (row.verdict != ProofVerdict.caught) continue;
      final declaration = enclosingDeclaration(lines, row.line);
      for (final test in row.caughtBy) {
        final counts = guardsByDeclaration.putIfAbsent(declaration, () => {});
        counts[test] = (counts[test] ?? 0) + 1;
      }
    }
    final survivors = byFile[file]!.where((r) => r.verdict == ProofVerdict.missed).toList()
      ..sort((a, b) => a.line.compareTo(b.line));
    for (final row in survivors) {
      anySurvivor = true;
      final declaration = enclosingDeclaration(lines, row.line);
      final guards = (guardsByDeclaration[declaration]?.entries.toList() ?? [])
        ..sort((a, b) => b.value.compareTo(a.value));
      final executed = lcov[file]?[row.line];
      out.writeln('- `$file:${row.line}` in `$declaration`: ${row.description}');
      out.writeln('  - run by the suite: ${executed == null ? 'not measured' : executed > 0 ? 'yes' : 'no, no test reaches this line'}');
      out.writeln(guards.isEmpty
          ? '  - add to: no test guards anything in `$declaration`; '
              '${mirroredTest(root, file) ?? 'the file has no mirrored test'}'
          : '  - add to the tests that guard `$declaration`: '
              '${guards.take(3).map((e) => e.key).join('; ')}');
    }
  }
  if (!anySurvivor) out.writeln('None.');

  final tierTwo = rows.where((r) => r.verdict == ProofVerdict.caught && r.tier == 2).toList();
  out
    ..writeln()
    ..writeln('## Lines only the wider suite guards (the mirrored test is weak or missing)')
    ..writeln();
  if (tierTwo.isEmpty) out.writeln('None.');
  for (final row in tierTwo) {
    out.writeln('- `${row.file}:${row.line}`: ${row.description} - caught by '
        '${row.caughtBy.take(2).join('; ')}');
  }

  final identical = identicalKillers(rows);
  out
    ..writeln()
    ..writeln('## Tests that kill exactly the same mutants')
    ..writeln()
    ..writeln('No mutant tells these tests apart. They may assert different things '
        'about the same logic (then keep both and say so) or the same thing '
        'twice (then merge, or link one to the other).')
    ..writeln();
  if (identical.isEmpty) out.writeln('None.');
  for (final group in identical.take(25)) {
    out.writeln('- ${group.kills} mutants: ${group.tests.take(4).join('; ')}'
        '${group.tests.length > 4 ? '; and ${group.tests.length - 4} more' : ''}');
  }

  final guarding = <String, int>{};
  for (final row in rows) {
    for (final test in row.caughtBy) {
      guarding[test] = (guarding[test] ?? 0) + 1;
    }
  }
  out
    ..writeln()
    ..writeln('## Tests, by how many lines they guard')
    ..writeln()
    ..writeln('| Test | Mutants it killed |')
    ..writeln('|---|---|');
  final ranked = guarding.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in ranked.take(30)) {
    out.writeln('| ${entry.key} | ${entry.value} |');
  }
  return out.toString();
}
