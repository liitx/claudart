import 'dart:async';
import 'dart:convert';

import 'package:claudart/commands/scope_files.dart';
import 'package:claudart/paths.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _ws = '/ws/proj';
const _root = '/work/proj';
const _scope = '### Files in play\n'
    '- `lib/a.dart` — inside\n'
    '- `../shared/x.dart` — sibling package\n'
    '- `../other/y.dart` — somewhere else\n';

/// Runs [readScopeFiles] with `print` captured; returns (relative paths, printed lines).
({List<String> files, List<String> printed}) _read(MemoryFileIO io, String scope) {
  final printed = <String>[];
  late List<String> files;
  Zone.current
      .fork(specification: ZoneSpecification(print: (self, parent, zone, line) => printed.add(line)))
      .run(() {
    files = readScopeFiles(scope: scope, projectRoot: _root, workspace: _ws, io: io)
        .map((f) => f.relative)
        .toList();
  });
  return (files: files, printed: printed);
}

void main() {
  late MemoryFileIO io;
  setUp(() => io = MemoryFileIO());

  test('default: paths outside the project are dropped and reported, with how to allow them', () {
    final r = _read(io, _scope);
    final text = r.printed.join('\n');
    expect(r.files, ['lib/a.dart']);
    expect(text, contains('Ignored 2 scope path(s) outside the project root'));
    expect(text, contains('../shared/x.dart'));
    expect(text, contains('../other/y.dart'));
    expect(text, contains('allowedScopeRoots'));
    expect(text, contains(configPathFor(_ws)));
  });

  test('allowedScopeRoots in the workspace config.json admits only the listed root', () {
    io.write(configPathFor(_ws), jsonEncode({'allowedScopeRoots': ['../shared']}));
    final r = _read(io, _scope);
    final text = r.printed.join('\n');
    expect(r.files, ['lib/a.dart', '../shared/x.dart']);
    expect(text, contains('Ignored 1 scope path(s)'));
    expect(text, contains('../other/y.dart'));
    expect(text, isNot(contains('- ../shared/x.dart')));
  });

  test('nothing is printed when every path is inside the project', () {
    final r = _read(io, '### Files in play\n- `lib/a.dart` — x\n');
    expect(r.files, ['lib/a.dart']);
    expect(r.printed, isEmpty);
  });

  test('a malformed config.json falls back to strict containment', () {
    io.write(configPathFor(_ws), '{ not json');
    expect(_read(io, _scope).files, ['lib/a.dart']);
  });

  test('blank or non-string entries in allowedScopeRoots are ignored', () {
    io.write(configPathFor(_ws), jsonEncode({'allowedScopeRoots': ['', 7, null, '../shared']}));
    expect(_read(io, _scope).files, ['lib/a.dart', '../shared/x.dart']);
  });
}
