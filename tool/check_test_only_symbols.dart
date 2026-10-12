// check_test_only_symbols.dart — advisory census: lib/ top-level symbols
// referenced only from test/, never from real lib/ or bin/ code.
//
// Text-matching only, no analyzer dependency — matches
// check_duplicate_literals.dart's own convention and keeps this tool's
// dependency ledger minimal. Intended to only under-report (a name
// collision, or a mention inside a comment/string, counts as "used," and
// Dart has no runtime string reflection to fool this the other way) —
// confirmed by independent review this still holds against the real repo
// today (no false hit), but the mechanism has known gaps worth naming
// rather than leaving implicit:
//   - A declaration-shaped line inside a `'''...'''` template string (e.g.
//     knowledge_templates.dart's embedded code samples) is parsed as a real
//     declaration. Harmless in practice so far — such a "declaration"
//     reliably collides with real template text elsewhere in its own file,
//     which the own-file liveness check already treats as "used."
//   - The "used in its own file" liveness check (ownFileOccurrences > 1) is
//     satisfied by a constructor call, a `.values` reference, or even a
//     mention inside the symbol's own `/// [Foo]` doc comment — a genuinely
//     unused top-level class with an unused constructor can look "live"
//     this way. This biases toward under-reporting, consistent with the
//     tool's design, but it's a real reason a hit could be missing, not
//     just name collisions.
//   - The barrel-export parser only recognizes single-quoted
//     `export '...' [show ...];` lines — a `hide` clause or a
//     double-quoted export would be silently treated as a whole-file
//     export (or missed entirely), which could under- or over-count public
//     API. Not present in this repo's actual barrel today (checked).
// Advisory only, always exits 0 — a hard gate would fail immediately on
// this repo's own pre-existing hits, which are tracked, not fixed here.
//
// Scope: top-level declarations only (class/enum/mixin/extension/typedef/
// function/getter/const/final/var). Class and enum MEMBERS are
// deliberately out of scope — overrides, enum getters, and interface
// members would be far too noisy to judge by text alone. (A top-level
// getter, declared directly in a file rather than inside a class/enum, is
// different and is in scope — see `_topLevelGetterDecl`.)

import 'dart:io';

final _classDecl = RegExp(
    r'^(?:abstract\s+|sealed\s+|base\s+|final\s+|interface\s+|mixin\s+)*class\s+(\w+)');
final _enumDecl = RegExp(r'^enum\s+(\w+)');
final _mixinDecl = RegExp(r'^mixin\s+(\w+)');
final _extensionDecl = RegExp(r'^extension\s+(\w+)\s+on\b');
final _typedefDecl = RegExp(r'^typedef\s+(\w+)\s*[<=]');
final _topLevelVarDecl = RegExp(r'^(?:const|final|var)\s+(?:[\w<>,.? ]+\s+)?(\w+)\s*=');
final _topLevelFunctionDecl = RegExp(
  r'^(?:Future<[\w<>,.? ]*>\??|void|bool|int|double|num|dynamic|'
  r'[A-Z]\w*(?:<[\w<>,.? ]*>)?\??|[a-z]\w*\??)\s+(\w+)\s*(?:<[\w<>,.? ]*>)?\s*\(',
);
// Top-level only (column-anchored, so a class/enum member getter — already
// out of scope, see this file's own header — never matches: it's always
// indented). Missed in the first version: `String get workspacesRoot { ... }`
// in lib/paths.dart was invisible to the census entirely.
final _topLevelGetterDecl = RegExp(r'^(?:[\w<>,.? ]+\s+)?get\s+(\w+)\s*(?:=>|\{)');

List<RegExp> get _declPatterns => [
      _classDecl,
      _enumDecl,
      _mixinDecl,
      _extensionDecl,
      _topLevelGetterDecl,
      _typedefDecl,
      _topLevelVarDecl,
      _topLevelFunctionDecl,
    ];

/// One top-level declaration: its name and which file declared it.
typedef Declaration = ({String name, String file});

void main(List<String> args) {
  final libFiles = _dartFilesUnder('lib');
  final binFiles = _dartFilesUnder('bin');
  final testFiles = _dartFilesUnder('test');
  final contents = <String, String>{
    for (final f in [...libFiles, ...binFiles, ...testFiles]) f: File(f).readAsStringSync(),
  };

  const barrelPath = 'lib/claudart.dart';
  final publicApi = _publicApiSymbols(barrelPath, contents);

  final declarations = <Declaration>[
    for (final file in libFiles)
      if (file != barrelPath) ..._declarationsIn(file, contents[file]!),
  ];

  final hits = <String>[];
  for (final decl in declarations) {
    final name = decl.name;
    if (name.startsWith('_')) continue;
    if (publicApi.contains(name)) continue;

    final pattern = RegExp(r'\b' + RegExp.escape(name) + r'\b');
    final ownFileOccurrences = pattern.allMatches(contents[decl.file]!).length;
    final usedElsewhereInLib = libFiles
        .where((f) => f != decl.file && f != barrelPath)
        .any((f) => pattern.hasMatch(contents[f]!));
    final usedInBin = binFiles.any((f) => pattern.hasMatch(contents[f]!));
    if (ownFileOccurrences > 1 || usedElsewhereInLib || usedInBin) continue;

    final usedInTest = testFiles.any((f) => pattern.hasMatch(contents[f]!));
    if (usedInTest) hits.add('${decl.name} (${decl.file})');
  }

  if (hits.isEmpty) {
    stdout.writeln('✓ No test-only lib/ symbols found.');
    return;
  }

  stdout.writeln(
    '⚠️  ${hits.length} lib/ symbol${hits.length == 1 ? '' : 's'} referenced only from '
    'test/, never from real lib/ or bin/ code:',
  );
  for (final hit in hits) {
    stdout.writeln('   - $hit');
  }
  stdout.writeln('   Advisory only — verify before deleting anything this flags.');
}

List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList();
}

/// Builds the public-API symbol set from the barrel file's own export
/// lines. A `show` clause limits the set to exactly those names; no `show`
/// clause re-exports the whole file, so every top-level declaration in it
/// counts as public API.
Set<String> _publicApiSymbols(String barrelPath, Map<String, String> contents) {
  final barrelContent = contents[barrelPath];
  if (barrelContent == null) return {};
  final public = <String>{};
  final exportLine = RegExp(r"""export\s+'([^']+)'(?:\s+show\s+([^;]+))?;""");
  for (final match in exportLine.allMatches(barrelContent)) {
    final showClause = match.group(2);
    if (showClause != null) {
      public.addAll(showClause.split(',').map((s) => s.trim()));
      continue;
    }
    final exportedPath = 'lib/${match.group(1)!}';
    final exportedContent = contents[exportedPath];
    if (exportedContent == null) continue;
    for (final decl in _declarationsIn(exportedPath, exportedContent)) {
      public.add(decl.name);
    }
  }
  return public;
}

List<Declaration> _declarationsIn(String file, String content) {
  final found = <Declaration>[];
  for (final line in content.split('\n')) {
    // A real bug, caught by its own output: the optional return-type group
    // in several patterns (e.g. _topLevelGetterDecl) includes a literal
    // space in its character class, so it can absorb leading indentation
    // and match an indented class/enum member as if it were top-level —
    // `  bool get canUpdateReadme => ...;` inside `enum WorkspaceRole`
    // matched and was flagged as a false "test-only" hit before this
    // guard. dart format never indents a real top-level declaration, so
    // skipping any indented line is both correct and simpler than trying
    // to patch every pattern's character class individually.
    if (line.startsWith(' ') || line.startsWith('\t')) continue;
    for (final pattern in _declPatterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        found.add((name: match.group(1)!, file: file));
        break;
      }
    }
  }
  return found;
}
