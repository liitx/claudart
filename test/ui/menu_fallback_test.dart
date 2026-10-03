import 'package:claudart/ui/menu.dart';
import 'package:test/test.dart';

class _Exit implements Exception {
  _Exit(this.code);
  final int code;
}

Never _throwExit(int code) => throw _Exit(code);

void main() {
  const items = ['apply (write all files to disk)', 'exit (quit without writing)'];

  group('selectNumbered', () {
    test('returns the 0-based index of a valid choice', () {
      final out = StringBuffer();
      final idx = selectNumbered(items,
          readLine: () => '2', write: out.write, writeError: (_) {}, exitFn: _throwExit);
      expect(idx, 1);
      expect(out.toString(), contains('1. apply'));
      expect(out.toString(), contains('2. exit'));
    });

    test('trims whitespace around the number', () {
      expect(
          selectNumbered(items,
              readLine: () => '  1  ', write: (_) {}, writeError: (_) {}, exitFn: _throwExit),
          0);
    });

    test('re-prompts after non-numeric and out-of-range input', () {
      final answers = ['abc', '0', '3', '2'].iterator;
      final out = StringBuffer();
      final idx = selectNumbered(items,
          readLine: () => answers.moveNext() ? answers.current : null,
          write: out.write,
          writeError: (_) {},
          exitFn: _throwExit);
      expect(idx, 1);
      expect('Enter a number between 1 and 2.'.allMatches(out.toString()).length, 3);
    });

    test('end of input aborts with exit code 1 and does NOT pick the first item', () {
      final err = <String>[];
      expect(
        () => selectNumbered(items,
            readLine: () => null, write: (_) {}, writeError: err.add, exitFn: _throwExit),
        throwsA(isA<_Exit>().having((e) => e.code, 'code', 1)),
      );
      expect(err.single, contains('No input available'));
      expect(err.single, contains('Nothing was selected'));
    });

    test('end of input after a bad answer still aborts (no silent default)', () {
      final answers = ['nope'].iterator;
      expect(
        () => selectNumbered(items,
            readLine: () => answers.moveNext() ? answers.current : null,
            write: (_) {},
            writeError: (_) {},
            exitFn: _throwExit),
        throwsA(isA<_Exit>()),
      );
    });
  });
}
