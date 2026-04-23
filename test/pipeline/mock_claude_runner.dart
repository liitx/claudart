// mock_claude_runner.dart — injectable ClaudeRunner for pipeline tests
//
// Returns predefined XML per step id without spawning a real claude process.
// Captures model, system prompt, and message for assertion in tests.

import 'package:claudart/claudart.dart';

class CallRecord {
  final AgentModel model;
  final String systemPrompt;
  final String message;
  const CallRecord({
    required this.model,
    required this.systemPrompt,
    required this.message,
  });
}

class MockClaudeRunner {
  MockClaudeRunner(this.responses);

  /// stepId → XML text to return when that step is called.
  final Map<String, String> responses;

  final List<CallRecord> captured = [];

  /// Returns a ClaudeRunner that matches responses by checking the message
  /// for a step-id sentinel (or falls back to the first response).
  ClaudeRunner get runner => ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
      }) async {
        captured.add(CallRecord(
          model:        model,
          systemPrompt: systemPrompt,
          message:      message,
        ));
        // Find first response whose key appears in the message; fallback to first entry.
        final text = responses.entries
                .where((e) => message.contains(e.key))
                .map((e) => e.value)
                .firstOrNull ??
            responses.values.firstOrNull ??
            '';
        return (text: text, usage: const Usage(input: 100, output: 50, cacheRead: 0, cost: 0.001));
      };
}
