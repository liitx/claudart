// flow_steps_test.dart — FlowSteps.clarify's postProcess contract, and
// FlowSteps.plan/construct's _projectIndex directory/enum guardrail
// (exercised indirectly via buildPrompt — _projectIndex itself is private).

import 'dart:io';

import 'package:claudart/pipeline/flows/flow_steps.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';

PipelineContext _ctx({String projectRoot = _projectRoot}) => PipelineContext(
      projectRoot: projectRoot,
      bug: '',
      expected: '',
      files: const [],
    );

void main() {
  group('FlowSteps.construct system prompt', () {
    test('seeds the handoff with the readyForSuggest wire value', () {
      expect(
        FlowSteps.construct.systemPrompt,
        contains('## Status\nready-for-suggest\n\n'),
      );
    });
  });

  group('FlowSteps.clarify.postProcess', () {
    test('untagged prose is wrapped in <ANSWER>', () {
      final result = FlowSteps.clarify.postProcess!('the label field is String?', _ctx());
      expect(result, equals('<ANSWER>the label field is String?</ANSWER>'));
    });

    test('output already containing <ANSWER> is left unchanged', () {
      const tagged = '<ANSWER>label is String?</ANSWER>';
      final result = FlowSteps.clarify.postProcess!(tagged, _ctx());
      expect(result, equals(tagged));
    });

    test('output already containing <UNKNOWN> is left unchanged', () {
      const tagged = '<UNKNOWN>not enough context to say</UNKNOWN>';
      final result = FlowSteps.clarify.postProcess!(tagged, _ctx());
      expect(result, equals(tagged));
    });

    test('empty output is still wrapped — an empty ANSWER, not silently dropped', () {
      final result = FlowSteps.clarify.postProcess!('', _ctx());
      expect(result, equals('<ANSWER></ANSWER>'));
    });
  });

  group('_projectIndex — via FlowSteps.plan.buildPrompt', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('flow_steps_test_');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    String promptFor(String projectRoot) =>
        FlowSteps.plan.buildPrompt(_ctx(projectRoot: projectRoot));

    test('scans lib/ directly — a plain Dart package with no lib/src/, '
        'like this repo itself', () {
      Directory('${tempRoot.path}/lib/commands').createSync(recursive: true);
      Directory('${tempRoot.path}/test').createSync(recursive: true);

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('Existing directories'));
      expect(prompt, contains('  lib'));
      expect(prompt, contains('  lib/commands'));
      expect(prompt, contains('  test'));
    });

    test('also covers lib/src/ where a project uses that convention', () {
      Directory('${tempRoot.path}/lib/src/features').createSync(recursive: true);

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('  lib/src'));
      expect(prompt, contains('  lib/src/features'));
    });

    test('directory names are sorted, independent of filesystem creation order', () {
      Directory('${tempRoot.path}/lib/zebra').createSync(recursive: true);
      Directory('${tempRoot.path}/lib/apple').createSync(recursive: true);

      final prompt = promptFor(tempRoot.path);
      final zebraLine = prompt.indexOf('lib/zebra');
      final appleLine = prompt.indexOf('lib/apple');

      expect(appleLine, greaterThan(0));
      expect(zebraLine, greaterThan(0));
      expect(appleLine, lessThan(zebraLine));
    });

    test('an unreadable directory does not abort the scan — sibling entries '
        'still appear', () {
      final blocked = Directory('${tempRoot.path}/lib/blocked')..createSync(recursive: true);
      Directory('${tempRoot.path}/lib/ok').createSync(recursive: true);
      // 0 perms — listSync on this dir throws FileSystemException.
      Process.runSync('chmod', ['000', blocked.path]);

      addTearDown(() => Process.runSync('chmod', ['755', blocked.path]));

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('  lib/ok'));
    }, skip: Platform.isWindows ? 'chmod is POSIX-only' : false);

    test('neither test/ nor lib/ exists → no directory block emitted', () {
      final prompt = promptFor(tempRoot.path);
      expect(prompt, isNot(contains('Existing directories')));
    });

    test('scan past the entry cap surfaces a truncation line — the cap only '
        'bounds what dirs.length can hold, so "truncated" must come from the '
        'walk itself, not from comparing dirs.length against the cap', () {
      // 310 directories: past the 300-entry cap the walk stops at.
      for (var i = 0; i < 310; i++) {
        Directory('${tempRoot.path}/lib/d$i').createSync(recursive: true);
      }

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('more exist'));
    });

    test('lib/src/enums/ with an enum declaration → named in the prompt', () {
      final enumsDir = Directory('${tempRoot.path}/lib/src/enums')..createSync(recursive: true);
      File('${enumsDir.path}/status.dart').writeAsStringSync('enum Status { ok, error }');

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('Known enum types'));
      expect(prompt, contains('Status'));
    });

    test('an indented enum declaration (leading whitespace after a '
        'conditional import/comment) is still found — the regex must not '
        'anchor to column 0', () {
      final enumsDir = Directory('${tempRoot.path}/lib/src/enums')..createSync(recursive: true);
      File('${enumsDir.path}/mode.dart').writeAsStringSync(
        "import 'dart:io' if (dart.library.html) 'dart:html';\n\n"
        '  enum Mode { fast, slow }\n',
      );

      final prompt = promptFor(tempRoot.path);

      expect(prompt, contains('Known enum types'));
      expect(prompt, contains('Mode'));
    });

    test('no lib/src/enums/ → no "Known enum types" line', () {
      Directory('${tempRoot.path}/lib').createSync(recursive: true);
      final prompt = promptFor(tempRoot.path);
      expect(prompt, isNot(contains('Known enum types')));
    });

    test('lib/src/enums/ itself unreadable does not abort the whole scan — '
        'the directory listing call, not just the per-file reads, must be '
        'guarded', () {
      final enumsDir = Directory('${tempRoot.path}/lib/src/enums')..createSync(recursive: true);
      Process.runSync('chmod', ['000', enumsDir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', enumsDir.path]));

      expect(() => promptFor(tempRoot.path), returnsNormally);
      final prompt = promptFor(tempRoot.path);
      expect(prompt, isNot(contains('Known enum types')));
    }, skip: Platform.isWindows ? 'chmod is POSIX-only' : false);
  });
}
