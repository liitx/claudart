import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

import 'scripted_claude_runner.dart';

Future<StepResult?> _call(
  ScriptedClaudeRunner fake,
  AgentStep step, {
  AgentModel model = AgentModel.sonnet,
  String message = 'msg',
}) =>
    fake.runner(
      model: model,
      systemPrompt: step.systemPrompt,
      message: message,
      workingDir: '/tmp/p',
    );

void main() {
  final reader = SuggestSteps.reader(1);
  const reasoner = SuggestSteps.reasoner;

  group('ScriptedClaudeRunner', () {
    test('answers each call from the reply scripted for its step', () async {
      final fake = ScriptedClaudeRunner({reader: 'READER', reasoner: 'REASON'});
      expect((await _call(fake, reasoner))!.text, 'REASON');
      expect((await _call(fake, reader))!.text, 'READER');
    });

    test('an unscripted call throws, naming the model and the prompt', () {
      final fake = ScriptedClaudeRunner({reader: 'READER'});
      expect(
        () => _call(fake, reasoner, model: AgentModel.opus),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('opus'),
                contains(reasoner.systemPrompt.substring(0, 20))),
          ),
        ),
      );
    });

    test(
        'steps that share a system prompt are answered in the order '
        'scripted', () async {
      // reader(1) and reader(2) differ only in their message, not their
      // system prompt, like the real planner and applier.
      final first = SuggestSteps.reader(1);
      final second = SuggestSteps.reader(2);
      final fake = ScriptedClaudeRunner({first: 'FIRST', second: 'SECOND'});
      expect((await _call(fake, first))!.text, 'FIRST');
      expect((await _call(fake, first))!.text, 'SECOND');
    });

    test('a call beyond the replies scripted for its prompt throws', () async {
      final fake = ScriptedClaudeRunner({reader: 'ONLY'});
      await _call(fake, reader);
      expect(
        () => _call(fake, reader),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already used'),
          ),
        ),
      );
    });

    test('records every call, in order, as typed values', () async {
      final fake = ScriptedClaudeRunner({reader: 'R', reasoner: 'S'});
      await _call(fake, reasoner, model: AgentModel.opus, message: 'one');
      await _call(fake, reader, model: AgentModel.haiku, message: 'two');
      expect(fake.calls.map((c) => (c.model, c.message)), [
        (AgentModel.opus, 'one'),
        (AgentModel.haiku, 'two'),
      ]);
    });

    test('unusedSteps lists the scripted steps never called', () async {
      final fake = ScriptedClaudeRunner({reader: 'R', reasoner: 'S'});
      await _call(fake, reader);
      expect(fake.unusedSteps, [reasoner]);
    });

    test('every reply carries the usage it was given', () async {
      final fake = ScriptedClaudeRunner(
        {reader: 'R'},
        usage: const Usage(input: 7, output: 3, cacheRead: 0, cost: 0.5),
      );
      final result = await _call(fake, reader);
      expect(result!.usage.input, 7);
      expect(result.usage.output, 3);
      expect(result.usage.cost, 0.5);
    });
  });
}
