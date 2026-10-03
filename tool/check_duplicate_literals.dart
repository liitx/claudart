// check_duplicate_literals.dart — PostToolUse hook backend, not a CLI command
//
// Advisory, not a gate: `custom_lint`'s `bare_string_for_enum` only fires on
// switch-dispatch over string literals — a plain literal value repeated in
// two unrelated call sites (confirmed real: 'which' and ['auth', 'status']
// both duplicated this way in a single PR) has no mechanical check at all
// today. This closes that gap by running automatically after every
// Edit/Write via `.claude/settings.json`'s PostToolUse hook, instead of
// depending on a human or agent remembering to grep for it afterward.
//
// Deliberately simple: same-file duplication only, string literals only
// (no list/map literal comparison), no attempt to resolve which repeats are
// "real" violations vs. coincidental — false positives are cheap here since
// this only ever prints a nudge, it never blocks the edit.

import 'dart:io';

// Two separate same-quote patterns, not `['"]...['"]` — a single combined
// pattern lets the "close" of one literal and the "open" of the next
// (e.g. the ternary `'entry' : 'entries'`) match as if the text between
// them, `' : '`, were itself a literal. Real bug, caught by testing this
// script against this repo's own files before wiring it in anywhere.
final _singleQuoted = RegExp(r"'([^']{3,})'");
final _doubleQuoted = RegExp(r'"([^"]{3,})"');
final _directiveLine = RegExp(r'^\s*(import|export|part)\s');

void main(List<String> args) {
  if (args.isEmpty) return;
  final path = args.first;
  // Test fixtures legitimately repeat literal values constantly (env var
  // names, sample paths) across unrelated cases — that's expected data,
  // not a paradigm violation. Scoped to lib/ only, matching this repo's
  // existing PostToolUse hook's own precedent.
  if (!path.endsWith('.dart') || !path.contains('/lib/')) return;
  final file = File(path);
  if (!file.existsSync()) return;

  final counts = <String, int>{};
  for (final line in file.readAsLinesSync()) {
    if (_directiveLine.hasMatch(line)) continue;
    for (final pattern in [_singleQuoted, _doubleQuoted]) {
      for (final match in pattern.allMatches(line)) {
        final literal = match.group(1)!;
        counts[literal] = (counts[literal] ?? 0) + 1;
      }
    }
  }

  final repeated = counts.entries.where((e) => e.value > 1).map((e) => e.key).toList();
  if (repeated.isEmpty) return;

  stdout.writeln(
    '⚠️  Repeated string literal${repeated.length == 1 ? '' : 's'} in '
    '$path: ${repeated.map((s) => "'$s'").join(', ')} — extract to a named '
    'const/enum getter if this is a real duplicate, per CLAUDE.md\'s no-bare-'
    'strings rule.',
  );
}
