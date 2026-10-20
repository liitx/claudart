// chat_shell_test.dart — the chat-first command parser (matrix) and the
// hermetic read→parse→dispatch loop. Conversation is the default: plain text is
// a message, only slash commands invoke.

import 'package:claudart/commands/chat_shell.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/step_role.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCommand.parse — conversation is the default', () {
    const cases = <String, ChatCommand>{
      'hello there':  ChatCommand.message, // plain text = conversation
      'flow':         ChatCommand.message, // no slash = NOT the command
      'what is flow?':ChatCommand.message,
      '/flow':        ChatCommand.flow,
      '/FLOW':        ChatCommand.flow,
      '  /flow ':     ChatCommand.flow,
      '/flow now':    ChatCommand.flow,
      '/suggest':     ChatCommand.suggest,
      '/quit':        ChatCommand.quit,
      '/exit':        ChatCommand.quit,
      '/q':           ChatCommand.quit,
      '/help':        ChatCommand.help,
      '/nope':        ChatCommand.help, // unrecognized command → help
      '':             ChatCommand.help,
    };

    cases.forEach((input, expected) {
      test('"$input" → ${expected.name}', () {
        expect(ChatCommand.parse(input), equals(expected));
      });
    });
  });

  // Answering a person's message is reasoning, so it runs on sonnet and may
  // only read, never on haiku and never with a tool that writes.
  group('answerChatMessage', () {
    AgentModel? receivedModel;
    Set<ClaudeTool>? receivedTools;
    AgentModel? receivedHelperModel;
    String? receivedMessage;
    String? receivedSystemPrompt;
    String? receivedWorkingDir;

    setUp(() {
      receivedModel = receivedHelperModel = null;
      receivedTools = null;
      receivedMessage = receivedSystemPrompt = receivedWorkingDir = null;
    });

    Future<StepResult?> answer({StepResult? reply}) => answerChatMessage(
          run: ({
            required model,
            required systemPrompt,
            required message,
            required workingDir,
            required allowedTools,
            required helperModel,
            StepMode mode = StepMode.project,
          }) async {
            receivedModel = model;
            receivedSystemPrompt = systemPrompt;
            receivedMessage = message;
            receivedWorkingDir = workingDir;
            receivedTools = allowedTools;
            receivedHelperModel = helperModel;
            return reply;
          },
          systemPrompt: 'the system prompt',
          history: ['you: hello', 'claudart: hi', 'you: and now?'],
          workingDir: '/projects/my-app',
        );

    const reply = StepResult(
      text: 'the reply',
      usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
    );

    test('runs on sonnet, never haiku', () async {
      await answer(reply: reply);
      expect(receivedModel, AgentModel.sonnet);
    });

    test('may only use the reasoning role\'s tools', () async {
      await answer(reply: reply);
      expect(receivedTools, StepRole.reasoning.allowedTools);
    });

    test('runs the CLI\'s helper calls on the reasoning role\'s helper model',
        () async {
      await answer(reply: reply);
      expect(receivedHelperModel, StepRole.reasoning.helperModel);
    });

    test('sends the whole history, oldest first, as the message', () async {
      await answer(reply: reply);
      expect(receivedMessage, 'you: hello\n\nclaudart: hi\n\nyou: and now?');
    });

    test('passes the system prompt and the project directory', () async {
      await answer(reply: reply);
      expect(receivedSystemPrompt, 'the system prompt');
      expect(receivedWorkingDir, '/projects/my-app');
    });

    test('returns the runner\'s reply', () async {
      expect(await answer(reply: reply), same(reply));
    });

    test('returns null when the runner gives nothing', () async {
      expect(await answer(), isNull);
    });
  });

  group('runChatLoop', () {
    test('plain text routes to onMessage; slash commands dispatch', () async {
      final lines = ['hello', '/flow', 'bye', '/quit', 'never'].iterator;
      final messages = <String>[];
      var flow = 0;
      await runChatLoop(
        readLine:  () => lines.moveNext() ? lines.current : null,
        out:       (_) {},
        onFlow:    () async => flow++,
        onSuggest: () async {},
        onMessage: (t) async => messages.add(t),
      );
      expect(messages, equals(['hello', 'bye']));
      expect(flow, equals(1)); // 'never' after /quit does not run
    });

    test('returns on EOF without hanging', () async {
      await runChatLoop(
        readLine:  () => null,
        out:       (_) {},
        onFlow:    () async {},
        onSuggest: () async {},
        onMessage: (_) async {},
      );
    });

    test('/help prints a hint and dispatches nothing', () async {
      final lines = ['/help', '/quit'].iterator;
      final out = <String>[];
      var touched = 0;
      await runChatLoop(
        readLine:  () => lines.moveNext() ? lines.current : null,
        out:       out.add,
        onFlow:    () async => touched++,
        onSuggest: () async => touched++,
        onMessage: (_) async => touched++,
      );
      expect(touched, equals(0));
      expect(out.length, equals(1));
    });
  });
}
