import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/md_io.dart';
import 'helpers/mocks.dart';

void main() {
  group('readSection', () {
    const doc = '''
## Bug

Widget does not update on state change.

---

## Root Cause

The state listener is not attached.

---

## Other

some content
''';

    test('returns trimmed section content', () {
      expect(readSection(doc, 'Bug'), 'Widget does not update on state change.');
    });

    test('strips trailing separator', () {
      expect(readSection(doc, 'Bug'), isNot(contains('---')));
    });

    test('returns fallback when section missing', () {
      expect(readSection(doc, 'Nonexistent'), '_Not yet determined._');
    });

    test('reads last section without trailing separator', () {
      expect(readSection(doc, 'Other'), 'some content');
    });
  });

  group('updateSection', () {
    const doc = '## Status\n\nold-status\n\n## Other\n\ncontent\n';

    test('replaces existing section content', () {
      final result = updateSection(doc, 'Status', 'new-status');
      expect(result, contains('new-status'));
      expect(result, isNot(contains('old-status')));
    });

    test('appends new section when not found', () {
      final result = updateSection(doc, 'Missing', 'added');
      expect(result, contains('## Missing'));
      expect(result, contains('added'));
    });
  });

  group('readStatus', () {
    test('extracts status value', () {
      const doc = '## Status\n\nsuggest-investigating\n';
      expect(readStatus(doc), 'suggest-investigating');
    });

    test('returns unknown when missing', () {
      expect(readStatus('no status here'), 'unknown');
    });
  });

  group('updateStatus', () {
    test('replaces status value', () {
      const doc = '## Status\n\nsuggest-investigating\n';
      final result = updateStatus(doc, 'ready-for-debug');
      expect(result, contains('ready-for-debug'));
      expect(result, isNot(contains('suggest-investigating')));
    });
  });

  group('readFile / writeFile (real disk via temp dir)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('claudart_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writeFile creates file and readFile returns its content', () {
      final path = '${tmp.path}/test.md';
      writeFile(path, 'hello');
      expect(readFile(path), 'hello');
    });

    test('writeFile creates missing parent directories', () {
      final path = '${tmp.path}/deep/nested/file.md';
      writeFile(path, 'content');
      expect(File(path).existsSync(), isTrue);
    });

    test('readFile returns empty string for missing file', () {
      expect(readFile('${tmp.path}/missing.md'), '');
    });
  });

  group('MemoryFileIO', () {
    test('write then read returns content', () {
      final io = MemoryFileIO();
      io.write('/a.md', 'hello');
      expect(io.read('/a.md'), 'hello');
    });

    test('fileExists returns false before write', () {
      expect(MemoryFileIO().fileExists('/x.md'), isFalse);
    });

    test('fileExists returns true after write', () {
      final io = MemoryFileIO();
      io.write('/x.md', '');
      expect(io.fileExists('/x.md'), isTrue);
    });

    test('dirExists returns true for created dir', () {
      final io = MemoryFileIO();
      io.createDir('/my/dir');
      expect(io.dirExists('/my/dir'), isTrue);
    });

    test('listFiles returns only direct children with extension', () {
      final io = MemoryFileIO(files: {
        '/dir/a.md': '',
        '/dir/b.md': '',
        '/dir/sub/c.md': '',
        '/dir/d.txt': '',
      });
      final result = io.listFiles('/dir', extension: '.md');
      expect(result, containsAll(['/dir/a.md', '/dir/b.md']));
      expect(result, isNot(contains('/dir/sub/c.md')));
      expect(result, isNot(contains('/dir/d.txt')));
    });
  });
}
