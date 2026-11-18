// What the tests did, drawn (visibility of the tests' own integrity): each
// traced check says what the test gave the code, what it expected, what it got,
// and which log rows it caused. A test that expects what the code returned by
// construction, or none at all, shows here.

import 'dart:convert';

import 'package:claudart/logging/trace_diagram.dart';
import 'package:test/test.dart';

TraceRow _row({
  String test = 'a test',
  String? obligation = 'record',
  String input = 'status',
  String expected = 'ok',
  String actual = 'ok',
  bool passed = true,
  int expectedAt = 1,
  int actualAt = 2,
  List<String> caused = const [],
}) =>
    TraceRow(
      test: test,
      obligation: obligation,
      input: input,
      expected: expected,
      actual: actual,
      passed: passed,
      expectedAt: expectedAt,
      actualAt: actualAt,
      caused: caused,
    );

void main() {
  group('a traced check', () {
    test('is drawn: the expectation first, then the call and what came back',
        () {
      expect(renderTraceDiagram(_row()), '''sequenceDiagram
    participant Test
    participant Code
    Note over Test: expected ok
    Test->>Code: status
    Code-->>Test: ok
    Note over Test: ✓ matches
''');
    });

    test('that did not match says so, with both values', () {
      final text = renderTraceDiagram(
          _row(expected: 'ok', actual: 'failed', passed: false));
      expect(text, contains('Note over Test: expected ok'));
      expect(text, contains('Code-->>Test: failed'));
      expect(text, contains('Note over Test: ✗ differs from the expectation'));
    });

    test('lists the log rows it caused', () {
      final text = renderTraceDiagram(
          _row(caused: ['interactions: status ok', 'gates: exit 0']));
      expect(text, contains('Note over Code: caused interactions: status ok'));
      expect(text, contains('Note over Code: caused gates: exit 0'));
    });

    test('cannot break the diagram', () {
      final text = renderTraceDiagram(
          _row(input: 'a;b\nc # d', expected: 'x;y', actual: 'p\nq'));
      expect(text, isNot(contains('a;b')));
      expect(text, isNot(contains('#')));
      expect(text, isNot(contains('p\nq')));
    });

    test('is cut when its text is long', () {
      final text = renderTraceDiagram(_row(actual: 'x' * 200));
      expect(text, contains('${'x' * 119}…'));
      expect(text, isNot(contains('x' * 121)));
    });

    test('keeps text of exactly 120 characters whole', () {
      final text = renderTraceDiagram(_row(actual: 'x' * 120));
      expect(text, contains('Code-->>Test: ${'x' * 120}\n'));
    });
  });

  group('a check whose expectation came after its answer', () {
    test('is flagged: the expectation must be recorded first', () {
      final late = _row(expectedAt: 5, actualAt: 3);
      expect(late.expectedFirst, isFalse);
      expect(renderTraceDiagram(late),
          contains('Note over Test: ⚠ the expectation was recorded after the answer'));
    });

    test('recorded in order is not flagged', () {
      expect(_row().expectedFirst, isTrue);
      expect(renderTraceDiagram(_row()), isNot(contains('⚠')));
    });
  });

  group('rows', () {
    test('round-trip through JSON', () {
      final original = _row(caused: ['gates: exit 0'], passed: false);
      final back = TraceRow.fromJson(original.toJson());
      expect(back.test, original.test);
      expect(back.obligation, original.obligation);
      expect(back.input, original.input);
      expect(back.expected, original.expected);
      expect(back.actual, original.actual);
      expect(back.passed, original.passed);
      expect(back.expectedAt, original.expectedAt);
      expect(back.actualAt, original.actualAt);
      expect(back.caused, original.caused);
    });

    test('a test with no obligation is unanchored', () {
      expect(_row(obligation: null).anchor, unanchoredObligation);
      expect(_row(obligation: 'order').anchor, 'order');
    });

    test('are read from JSONL, skipping what is not a row', () {
      final rows = traceRowsOfJsonl(
          '${_jsonLine(_row())}\n\nnot json\n{"a":1}\n');
      expect(rows, hasLength(1));
      expect(rows.single.test, 'a test');
    });
  });

  group('the html page', () {
    test('holds each check for Mermaid to draw, under its heading', () {
      final html = renderTraceHtml([_row(test: 'one'), _row(test: 'two')]);
      expect(html, contains('<title>claudart traced checks</title>'));
      expect(html, contains('<h1>Traced checks</h1>'));
      expect(html, contains('<h2>one — record</h2>'));
      expect('<pre class="mermaid">'.allMatches(html), hasLength(2));
      expect(html, contains('<script type="module">'));
    });

    test('escapes what a test wrote so it cannot become markup', () {
      final html = renderTraceHtml([_row(test: 'a<b>&c')]);
      expect(html, isNot(contains('a<b>')));
      expect(html, contains('a&lt;b&gt;&amp;c'));
    });

    test('says so when nothing was traced', () {
      expect(renderTraceHtml(const []), contains('No checks were traced.'));
    });
  });

  group('the page', () {
    test('counts the checks and the unanchored ones for each obligation', () {
      final page = renderTracePage([
        _row(obligation: 'record'),
        _row(obligation: 'record', passed: false),
        _row(obligation: 'order'),
        _row(obligation: null),
      ]);
      expect(page, contains('| record | 2 | 1 |'));
      expect(page, contains('| order | 1 | 1 |'));
      expect(page, contains('| $unanchoredObligation | 1 | 1 |'));
    });

    test('starts with the table of obligations, its header and its divider',
        () {
      final page = renderTracePage([_row()]);
      expect(page, startsWith('# Traced checks\n\n'
          '| obligation | checks | passed |\n'
          '|---|---|---|\n'
          '| record | 1 | 1 |\n'));
    });

    test('has a heading and a fenced diagram for each check', () {
      final page = renderTracePage([_row(test: 'one'), _row(test: 'two')]);
      expect(page, contains('## one — record'));
      expect(page, contains('## two — record'));
      expect('```mermaid'.allMatches(page), hasLength(2));
    });

    test('says so when nothing was traced', () {
      expect(renderTracePage(const []), contains('No checks were traced'));
    });
  });
}

String _jsonLine(TraceRow row) => jsonEncode(row.toJson());
