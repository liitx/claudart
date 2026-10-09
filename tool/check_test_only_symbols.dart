// check_test_only_symbols.dart — advisory census: lib/ top-level symbols
// referenced only from test/, never from real lib/ or bin/ code.
//
// Text-matching only, no analyzer dependency — matches
// check_duplicate_literals.dart's own convention and keeps this tool's
// dependency ledger minimal. Can only under-report: a name collision, or a
// mention inside a comment/string, counts as "used." Dart has no runtime
// string reflection to fool this the other way, so a real hit is a real
// hit. Advisory only, always exits 0 — a hard gate would fail immediately
// on this repo's own pre-existing hits, which are tracked, not fixed here.
//
// Scope: top-level declarations only (class/enum/mixin/extension/typedef/
// function/const/final/var). Class and enum members are deliberately out
// of scope — overrides, enum getters, and interface members would be far
// too noisy to judge by text alone.

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
  r'[A-Z]\w*(?:<[\w<>,.? ]*>)?\??|[a-z]\w*\??)\s+(\w+)\s*\(',
);

List<RegExp> get _declPatterns => [
      _classDecl,
      _enumDecl,
      _mixinDecl,
      _extensionDecl,
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
