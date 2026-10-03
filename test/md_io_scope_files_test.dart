import 'dart:io';

import 'package:claudart/md_io.dart';
import 'package:test/test.dart';

String _scope(List<String> bullets) => '## Scope\n\n### Files in play\n${bullets.join('\n')}\n\n### Key entry points in play\n- `foo()`\n';

List<String> _rel(String scope, String root) =>
    parseScopeFiles(scope, root).map((f) => f.relative).toList();

void main() {
  const root = '/proj';

  group('parseScopeFiles — accepted bullet shapes', () {
    test('original format: backticked relative path with an em dash', () {
      expect(_rel(_scope(['- `lib/a.dart` — fix the sign']), root), ['lib/a.dart']);
    });

    test('backticked path followed by a colon', () {
      expect(_rel(_scope(['- `lib/a.dart`: fix the sign']), root), ['lib/a.dart']);
    });

    test('plain relative path with colon, em dash, en dash and hyphen separators', () {
      final scope = _scope([
        '- lib/a.dart: colon',
        '- lib/b.dart — em dash',
        '- lib/c.dart – en dash',
        '- lib/d.dart - hyphen',
      ]);
      expect(_rel(scope, root), ['lib/a.dart', 'lib/b.dart', 'lib/c.dart', 'lib/d.dart']);
    });

    test('a bare path with no description', () {
      expect(_rel(_scope(['- lib/a.dart']), root), ['lib/a.dart']);
    });

    test('asterisk bullets', () {
      expect(_rel(_scope(['* lib/a.dart: x', '* `lib/b.dart` — y']), root), ['lib/a.dart', 'lib/b.dart']);
    });

    test('trailing comma or semicolon on the path is dropped', () {
      expect(_rel(_scope(['- lib/a.dart, then more']), root), ['lib/a.dart']);
    });

    test('resolves the absolute path against the project root', () {
      final files = parseScopeFiles(_scope(['- lib/a.dart: x']), root);
      expect(files.single.absolute, '/proj/lib/a.dart');
    });

    test('a backticked path with spaces is kept whole', () {
      expect(_rel(_scope(['- `lib/my file.dart` — x']), root), ['lib/my file.dart']);
    });
  });

  group('parseScopeFiles — absolute paths (what suggest actually produced)', () {
    test('the exact line observed from a real suggest run', () {
      const line = '- /proj/lib/calc.dart: On line 1, change `a - b` to `a + b`. '
          'Remove the `// BUG: should add` comment once the fix is in.';
      expect(_rel(_scope([line]), root), ['lib/calc.dart']);
    });

    test('absolute path outside the project is dropped', () {
      expect(_rel(_scope(['- /etc/passwd.conf: nope', '- `/other/x.dart` — nope']), root), isEmpty);
    });

    test('sibling directory sharing the project name as a prefix is not "inside"', () {
      expect(_rel(_scope(['- /proj-other/lib/a.dart: nope']), root), isEmpty);
    });

    test('symlinked project root matches the realpath a subprocess reports', () {
      final real = Directory.systemTemp.createTempSync('scope_real_');
      final link = '${Directory.systemTemp.path}/scope_link_${real.path.hashCode}';
      addTearDown(() {
        if (Link(link).existsSync()) Link(link).deleteSync();
        real.deleteSync(recursive: true);
      });
      File('${real.path}/lib/calc.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('int add(int a, int b) => a - b;');
      Link(link).createSync(real.path);

      final abs = '${real.resolveSymbolicLinksSync()}/lib/calc.dart';
      final files = parseScopeFiles(_scope(['- $abs: fix']), link);

      expect(files.single.relative, 'lib/calc.dart');
      expect(files.single.absolute, '$link/lib/calc.dart');
    });
  });

  group('parseScopeFiles — not files', () {
    test('prose bullets are ignored', () {
      final scope = _scope([
        '- No changes needed',
        '- N/A',
        '- None yet',
        '- Nothing to touch here.',
      ]);
      expect(_rel(scope, root), isEmpty);
    });

    test('an extensionless name needs backticks', () {
      expect(_rel(_scope(['- Makefile: x']), root), isEmpty);
      expect(_rel(_scope(['- `Makefile` — x']), root), ['Makefile']);
    });

    test('non-bullet lines are ignored', () {
      expect(_rel(_scope(['lib/a.dart, lib/b.dart']), root), isEmpty);
    });

    test('only the Files in play subsection is read', () {
      const scope = '## Scope\n\n### Key entry points in play\n- lib/x.dart: nope\n\n'
          '### Files in play\n- lib/a.dart: yes\n\n### Must not touch\n- lib/y.dart: nope\n';
      expect(_rel(scope, root), ['lib/a.dart']);
    });

    test('an empty scope section yields nothing', () {
      expect(parseScopeFiles('', root), isEmpty);
    });
  });
}
