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

import '../../test/helpers/topology_family.dart';
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

/// The operator (and occurrence) a mutant's description names.
String mutantId(String description) =>
    RegExp(r'^line \d+ ([\w#]+):').firstMatch(description)?.group(1) ?? '';

/// The key an accepted-equivalent registry uses for [row].
String equivalentKey(MutantRow row) => '${row.file}|${row.line}|${mutantId(row.description)}';

/// The accepted-equivalent registry: one `file|line|operator|reason` per line,
/// `#` for comments. A mutant that no test can tell from the original (an
/// unreachable branch, an equal-value comparison) stays out of the survivors only
/// by being named here with the reason, so an exemption is never silent.
Map<String, String> parseEquivalents(String text) {
  final accepted = <String, String>{};
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final parts = line.split('|');
    if (parts.length < 4 || parts.sublist(3).join('|').trim().isEmpty) {
      throw FormatException('an equivalent mutant needs file|line|operator|reason: $line');
    }
    accepted['${parts[0]}|${parts[1]}|${parts[2]}'] = parts.sublist(3).join('|').trim();
  }
  return accepted;
}

/// Why a mutant that no test failed for survived.
enum SurvivalCause {
  /// No test runs the line: it needs a test that reaches it.
  notRun,

  /// Tests run the line and assert nothing that depends on it: it needs an
  /// assertion in the tests that already run it.
  unasserted,

  /// The tracefile does not mention the line (no tracefile, or no executable code
  /// on it), so the cause is not known.
  unmeasured,
}

/// The cause of [row]'s survival, from [lcov] hit counts by file and line.
SurvivalCause survivalCause(MutantRow row, Map<String, Map<int, int>> lcov) {
  final hits = lcov[row.file]?[row.line];
  if (hits == null) return SurvivalCause.unmeasured;
  return hits > 0 ? SurvivalCause.unasserted : SurvivalCause.notRun;
}

/// Unaccepted survivors counted by file.
Map<String, int> survivorsByFile(List<MutantRow> rows, Map<String, String> equivalents) {
  final counts = <String, int>{};
  for (final row in unacceptedSurvivors(rows, equivalents)) {
    counts[row.file] = (counts[row.file] ?? 0) + 1;
  }
  return counts;
}

/// The baseline file for [counts]: files with survivors, sorted.
String renderBaseline(Map<String, int> counts) {
  final out = StringBuffer()
    ..writeln('# Surviving line mutants by file: the debt, which can only shrink.')
    ..writeln('# Regenerate with `make ledger-baseline` after a full ledger run.');
  for (final file in counts.keys.toList()..sort()) {
    if (counts[file]! > 0) out.writeln('$file|${counts[file]}');
  }
  return out.toString();
}

/// The counts a baseline file holds.
Map<String, int> parseBaseline(String text) => {
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
          line.split('|').first: int.parse(line.split('|').last),
    };

/// How [current] survivor counts stand against [baseline]: files that got worse
/// (a failure) and files that got better (to be written down).
({Map<String, ({int before, int now})> regressions, Map<String, ({int before, int now})> improvements})
    compareToBaseline(Map<String, int> current, Map<String, int> baseline) {
  final regressions = <String, ({int before, int now})>{};
  final improvements = <String, ({int before, int now})>{};
  for (final file in {...current.keys, ...baseline.keys}) {
    final before = baseline[file] ?? 0;
    final now = current[file] ?? 0;
    if (now > before) regressions[file] = (before: before, now: now);
    if (now < before) improvements[file] = (before: before, now: now);
  }
  return (regressions: regressions, improvements: improvements);
}

/// The surviving mutants of [rows] that [equivalents] does not accept.
List<MutantRow> unacceptedSurvivors(List<MutantRow> rows, Map<String, String> equivalents) => [
      for (final row in rows)
        if (row.verdict == ProofVerdict.missed && !equivalents.containsKey(equivalentKey(row))) row,
    ];

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

/// What a change to [line] of [file] affects: the tests to update, or that none
/// guards it and which tests guard the rest of its declaration.
String describeImpact(List<MutantRow> rows, String file, int line, List<String> lines) {
  final here = rows.where((r) => r.file == file && r.line == line).toList();
  if (here.isEmpty) {
    return '$file:$line: not measured (no mutant of this line: it has nothing an '
        'operator changes, or the file was not mutated)';
  }
  final guarding = testsGuarding(rows, file, line);
  if (guarding.isNotEmpty) {
    return '$file:$line is guarded; when it changes, update: ${guarding.join('; ')}';
  }
  final declaration = enclosingDeclaration(lines, line);
  final neighbors = <String, int>{};
  for (final row in rows) {
    if (row.file != file || row.verdict != ProofVerdict.caught) continue;
    if (enclosingDeclaration(lines, row.line) != declaration) continue;
    for (final test in row.caughtBy) {
      neighbors[test] = (neighbors[test] ?? 0) + 1;
    }
  }
  final ranked = neighbors.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return '$file:$line: no test fails when this line is wrong. '
      '${ranked.isEmpty ? 'No test guards anything in `$declaration` either.' : 'Add the assertion to the tests that guard `$declaration`: ${ranked.take(3).map((e) => e.key).join('; ')}'}';
}

/// The markdown ledger. [sources] holds each file's text, [lcov] the line hits
/// (empty when none was measured) and [root] finds the mirrored tests.
String renderLedger({
  required List<MutantRow> rows,
  required Map<String, String> sources,
  required Map<String, Map<int, int>> lcov,
  required String root,
  required String title,
  List<String> excludedTests = const [],
  Map<String, String> equivalents = const {},
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
  final familyTotals = <String, ({int files, int mutants, int survived, int notRun, int unasserted})>{};
  for (final entry in byFile.entries) {
    final family = topologyFamilyOf(sources[entry.key] ?? '');
    final key = '${family.role.name} x ${family.reach.name}';
    final previous = familyTotals[key] ?? (files: 0, mutants: 0, survived: 0, notRun: 0, unasserted: 0);
    final survivors = unacceptedSurvivors(entry.value, equivalents);
    int caused(SurvivalCause cause) =>
        survivors.where((r) => survivalCause(r, lcov) == cause).length;
    familyTotals[key] = (
      files: previous.files + 1,
      mutants: previous.mutants + entry.value.length,
      survived: previous.survived + survivors.length,
      notRun: previous.notRun + caused(SurvivalCause.notRun),
      unasserted: previous.unasserted + caused(SurvivalCause.unasserted),
    );
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
    ..writeln('## By family')
    ..writeln()
    ..writeln('| Family | Files | Mutants | Survived (not accepted) | of those, no test runs the line | of those, tests run it and assert nothing about it |')
    ..writeln('|---|---|---|---|---|---|');
  for (final key in familyTotals.keys.toList()..sort()) {
    final total = familyTotals[key]!;
    out.writeln('| $key | ${total.files} | ${total.mutants} | ${total.survived} | ${total.notRun} | ${total.unasserted} |');
  }
  out
    ..writeln()
    ..writeln('## By file')
    ..writeln()
    ..writeln('| File | Family | Mirrored test | Mutants | Caught by the mirror | Caught only by the wider suite | Survived | Accepted equivalent | Invalid | Lines run by the suite |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
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
    final home = homeTest(root, file);
    final family = topologyFamilyOf(sources[file] ?? '');
    final accepted = fileRows
        .where((r) => r.verdict == ProofVerdict.missed && equivalents.containsKey(equivalentKey(r)))
        .length;
    out.writeln('| `$file` | ${family.role.name} x ${family.reach.name} | '
        '${home == null ? 'none' : home.mirrored ? home.path : '${home.path} (not mirrored)'} | ${fileRows.length} | '
        '${count(ProofVerdict.caught, tier: 1)} | ${count(ProofVerdict.caught, tier: 2)} | '
        '${count(ProofVerdict.missed) - accepted} | $accepted | ${count(ProofVerdict.invalid)} | $coverage |');
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
    final survivors = unacceptedSurvivors(byFile[file]!, equivalents)
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

  final accepted = [
    for (final row in rows)
      if (row.verdict == ProofVerdict.missed && equivalents.containsKey(equivalentKey(row))) row,
  ];
  out
    ..writeln()
    ..writeln('## Accepted as equivalent (no test can tell them from the original)')
    ..writeln();
  if (accepted.isEmpty) out.writeln('None.');
  for (final row in accepted) {
    out.writeln('- `${row.file}:${row.line}` ${row.description} - ${equivalents[equivalentKey(row)]}');
  }
  final matched = {for (final row in rows) equivalentKey(row)};
  final stale = equivalents.keys.where((key) => !matched.contains(key)).toList();
  if (stale.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Registry entries no mutant matches (the line moved or the mutant is gone; remove them): '
          '${stale.map((k) => '`$k`').join(', ')}');
  }

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
