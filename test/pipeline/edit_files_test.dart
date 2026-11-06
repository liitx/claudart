
// edit_files_test.dart — parseEditFiles / applyEditFiles / WireTag.
//
// Wire tag text is always composed from WireTag so this file never spells a
// closing delimiter out literally.

import 'dart:io';

import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/pipeline/edit_files.dart';
import 'package:claudart/pipeline/xml_tags.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _block(String path, String body) =>
    '${WireTag.editFile.openPrefix} path="$path">\n'
    '$body\n${WireTag.editFile.close}';

String get _changesBlock =>
    '<${WireTag.changes.tagName}>x</${WireTag.changes.tagName}>';

void _write(String path, String content) {
  File(path).parent.createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

Matcher _throwsFailure(FailureType failure) => throwsA(
      isA<EditPlanException>().having((e) => e.failure, 'failure', failure),
    );

void main() {
  final close = WireTag.editFile.close;

  group('parseEditFiles', () {
    test('parses one block after a changes tag', () {
      final text = '$_changesBlock\n'
          '${_block('lib/a.dart', 'void a() {}')}';
      expect(
        parseEditFiles(text),
        equals([(path: 'lib/a.dart', content: 'void a() {}\n')]),
      );
    });

    test('content containing the closing tag mid-line is kept intact', () {
      final body = 'before $close after\nlast line';
      final files = parseEditFiles(_block('lib/a.dart', body));
      expect(files.single.content, equals('$body\n'));
    });

    test('two files, first containing the closing tag, both parse', () {
      final text = '${_block('lib/a.dart', 'x $close y')}\n'
          '${_block('lib/b.dart', 'b')}';
      final files = parseEditFiles(text);
      expect(files.map((f) => f.path), equals(['lib/a.dart', 'lib/b.dart']));
      expect(files.first.content, equals('x $close y\n'));
      expect(files.last.content, equals('b\n'));
    });

    test('no file blocks yields an empty plan', () {
      expect(parseEditFiles(_changesBlock), isEmpty);
    });

    test('unterminated block is malformed', () {
      final text = '${WireTag.editFile.openPrefix} path="lib/a.dart">\nno end';
      expect(() => parseEditFiles(text),
          _throwsFailure(FailureType.editPlanMalformed));
    });

    test('text after the last closing tag is malformed, not truncation', () {
      final text = '${_block('lib/a.dart', 'a')}\nstray prose';
      expect(() => parseEditFiles(text),
          _throwsFailure(FailureType.editPlanMalformed));
    });

    test('open prefix without a valid path attribute is malformed', () {
      final text = '${WireTag.editFile.openPrefix}>\nbody\n$close';
      expect(() => parseEditFiles(text),
          _throwsFailure(FailureType.editPlanMalformed));
    });
  });

  group('applyEditFiles', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('edit_files_test'));
    tearDown(() => root.deleteSync(recursive: true));

    test('writes and verifies every planned file', () {
      applyEditFiles(
        projectRoot: root.path,
        planned: [
          (path: 'lib/a.dart', content: 'a $close b\n'),
          (path: 'notes.txt', content: 'n\n'),
        ],
        write: _write,
        dartFileAnalyzer: (_, __) => true,
      );
      expect(File(p.join(root.path, 'lib/a.dart')).readAsStringSync(),
          equals('a $close b\n'));
      expect(File(p.join(root.path, 'notes.txt')).readAsStringSync(), 'n\n');
    });

    test('analyze failure restores originals and removes new files', () {
      _write(p.join(root.path, 'lib/old.dart'), 'original\n');
      expect(
        () => applyEditFiles(
          projectRoot: root.path,
          planned: [
            (path: 'lib/old.dart', content: 'changed\n'),
            (path: 'lib/new.dart', content: 'fresh\n'),
          ],
          write: _write,
          dartFileAnalyzer: (_, __) => false,
        ),
        _throwsFailure(FailureType.editVerificationFailed),
      );
      expect(File(p.join(root.path, 'lib/old.dart')).readAsStringSync(),
          equals('original\n'));
      expect(File(p.join(root.path, 'lib/new.dart')).existsSync(), isFalse);
    });

    test('a verifier that fails restores originals and says the fix was not '
        'verified', () {
      _write(p.join(root.path, 'lib/old.dart'), 'original\n');
      expect(
        () => applyEditFiles(
          projectRoot: root.path,
          planned: [(path: 'lib/old.dart', content: 'changed\n')],
          write: _write,
          dartFileAnalyzer: (_, __) => true,
          verifyFix: (_) => false,
        ),
        _throwsFailure(FailureType.fixVerificationFailed),
      );
      expect(File(p.join(root.path, 'lib/old.dart')).readAsStringSync(),
          equals('original\n'));
    });

    test('a verifier runs once, after the files are written and analyzed', () {
      final seen = <String>[];
      applyEditFiles(
        projectRoot: root.path,
        planned: [(path: 'lib/a.dart', content: 'a\n')],
        write: _write,
        dartFileAnalyzer: (_, __) {
          seen.add('analyzed');
          return true;
        },
        verifyFix: (projectRoot) {
          seen.add('verified in ${p.basename(projectRoot)}');
          seen.add('file present: ${File(p.join(projectRoot, 'lib/a.dart')).existsSync()}');
          return true;
        },
      );
      expect(seen, [
        'analyzed',
        'verified in ${p.basename(root.path)}',
        'file present: true',
      ]);
    });

    test('a verifier is not asked when the analysis already failed', () {
      var asked = false;
      expect(
        () => applyEditFiles(
          projectRoot: root.path,
          planned: [(path: 'lib/a.dart', content: 'a\n')],
          write: _write,
          dartFileAnalyzer: (_, __) => false,
          verifyFix: (_) {
            asked = true;
            return true;
          },
        ),
        _throwsFailure(FailureType.editVerificationFailed),
      );
      expect(asked, isFalse);
    });

    test('with no verifier nothing is run', () {
      applyEditFiles(
        projectRoot: root.path,
        planned: [(path: 'lib/a.dart', content: 'a\n')],
        write: _write,
        dartFileAnalyzer: (_, __) => true,
      );
      expect(File(p.join(root.path, 'lib/a.dart')).existsSync(), isTrue);
    });

    test('a writer that truncates is caught by the content check', () {
      expect(
        () => applyEditFiles(
          projectRoot: root.path,
          planned: [(path: 'notes.txt', content: 'full content\n')],
          write: (path, content) => _write(path, content.substring(0, 4)),
          dartFileAnalyzer: (_, __) => true,
        ),
        _throwsFailure(FailureType.editVerificationFailed),
      );
      expect(File(p.join(root.path, 'notes.txt')).existsSync(), isFalse);
    });

    test('a writer that writes nothing is caught by the exists check', () {
      expect(
        () => applyEditFiles(
          projectRoot: root.path,
          planned: [(path: 'notes.txt', content: 'x\n')],
          write: (_, __) {},
          dartFileAnalyzer: (_, __) => true,
        ),
        _throwsFailure(FailureType.editVerificationFailed),
      );
    });

    test('non-dart files are not analyzed', () {
      var analyzed = 0;
      applyEditFiles(
        projectRoot: root.path,
        planned: [(path: 'notes.txt', content: 'x\n')],
        write: _write,
        dartFileAnalyzer: (_, __) {
          analyzed++;
          return false;
        },
      );
      expect(analyzed, 0);
    });
  });
}