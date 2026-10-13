// scripted_claude_runner.dart — a ClaudeRunner that replies per step.
//
// Replies are keyed by the real AgentStep and matched on its exact system
// prompt (the executor passes `step.systemPrompt` verbatim), so a test says
// which step gets which reply instead of hoping a substring of the message
// picks the right one. Steps that share a system prompt (the real planner and
// applier differ only in their message) are answered in the order they are
// scripted. The old MockClaudeRunner matched on message.contains and silently
// fell back to its first reply, so a call it was never told about still
// "worked". Here an unscripted call throws, naming the model and prompt, and a
// scripted step that is never called shows up in [unusedSteps].

import 'package:claudart/claudart.dart';

/// One call the fake received, as typed data.
class ClaudeRunnerCall {
  const ClaudeRunnerCall({
    required this.model,
    required this.systemPrompt,
    required this.message,
    required this.mode,
  });

  final AgentModel model;
  final String systemPrompt;
  final String message;
  final StepMode mode;
}

class ScriptedClaudeRunner {
  ScriptedClaudeRunner(
    Map<AgentStep, String> replies, {
    this.usage = const Usage(input: 100, output: 50, cacheRead: 0, cost: 0.001),
  }) {
    for (final entry in replies.entries) {
      _byPrompt
          .putIfAbsent(entry.key.systemPrompt, () => [])
          .add(_Scripted(entry.key, entry.value));
    }
  }

  /// What every reply reports as its token usage.
  final Usage usage;

  final Map<String, List<_Scripted>> _byPrompt = {};

  /// Every call received, in order.
  final List<ClaudeRunnerCall> calls = [];

  ClaudeRunner get runner => ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
        StepMode mode = StepMode.project,
      }) async {
        calls.add(
          ClaudeRunnerCall(
            model: model,
            systemPrompt: systemPrompt,
            message: message,
            mode: mode,
          ),
        );
        final head =
            systemPrompt.substring(0, systemPrompt.length.clamp(0, 60));
        final scripted = _byPrompt[systemPrompt];
        if (scripted == null) {
          throw StateError(
            'Unscripted model call: ${model.name}, system prompt starts '
            '"$head" -- script a reply for that step',
          );
        }
        final next = scripted.where((s) => !s.used).firstOrNull;
        if (next == null) {
          throw StateError(
            'Unscripted model call: ${model.name}, system prompt starts '
            '"$head" -- all ${scripted.length} replies scripted for it were '
            'already used',
          );
        }
        next.used = true;
        return StepResult(text: next.text, usage: usage);
      };

  /// Scripted steps that were never called.
  List<AgentStep> get unusedSteps => [
        for (final scripted in _byPrompt.values)
          for (final s in scripted)
            if (!s.used) s.step,
      ];
}

class _Scripted {
  _Scripted(this.step, this.text);

  final AgentStep step;
  final String text;
  bool used = false;
}
