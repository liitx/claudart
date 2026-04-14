import 'package:test/test.dart';
import 'package:claudart/ui/line_editor.dart';

void main() {
  group('wrappedLineCount', () {
    const cases = [
      (description: 'empty input',            promptLen: 2, bufLen:   0, termWidth: 80, expected: 1),
      (description: 'exactly fills one line', promptLen: 2, bufLen:  78, termWidth: 80, expected: 1),
      (description: 'one char past width',    promptLen: 2, bufLen:  79, termWidth: 80, expected: 2),
      (description: 'two full lines',         promptLen: 2, bufLen: 158, termWidth: 80, expected: 2),
      (description: 'start of third line',    promptLen: 2, bufLen: 159, termWidth: 80, expected: 3),
      (description: 'zero termWidth',         promptLen: 2, bufLen: 200, termWidth:  0, expected: 1),
      (description: 'narrow terminal',        promptLen: 2, bufLen:   8, termWidth:  5, expected: 2),
      (description: 'prompt fills line',      promptLen: 80, bufLen:  0, termWidth: 80, expected: 1),
    ];

    for (final c in cases) {
      test(c.description, () {
        expect(
          wrappedLineCount(c.promptLen, c.bufLen, c.termWidth),
          c.expected,
        );
      });
    }
  });
}
