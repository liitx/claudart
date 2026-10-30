// User text lives in text/user_text.json (invariant I6): a command prints
// words it gets from `UserText`, not a sentence written at the call site.
// The count of printed literals only goes down.

import 'dart:io';

import 'package:test/test.dart';

/// A sentence of twelve characters or more passed straight to `print`.
final _printedLiteral = RegExp('''print\\(\\s*(['"])(?:(?!\\1).){12,}\\1''');

/// Sentences printed from a literal in `lib/commands`, and the files that
/// hold them.
Map<String, int> printedLiteralsByFile(Map<String, String> sources) => {
      for (final entry in sources.entries)
        if (_printedLiteral.allMatches(entry.value).isNotEmpty)
          entry.key: _printedLiteral.allMatches(entry.value).length,
    };

const _knownPrintedLiterals = 71;

void main() {
  group('user text', () {
    test('a printed sentence is found, a printed text key is not', () {
      expect(
        printedLiteralsByFile({'a': "print('Something went wrong here');"}),
        {'a': 1},
      );
      expect(
        printedLiteralsByFile({'a': 'print(UserText.killCancelled.template);'}),
        isEmpty,
      );
    });

    test('printed literals in lib/commands do not grow', () {
      final sources = {
        for (final file in Directory('lib/commands')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
      };
      final found = printedLiteralsByFile(sources);
      final total = found.values.fold(0, (sum, count) => sum + count);
      expect(
        total,
        lessThanOrEqualTo(_knownPrintedLiterals),
        reason: 'user text belongs in text/user_text.json. Found $total in: '
            '$found',
      );
    });
  });
}
