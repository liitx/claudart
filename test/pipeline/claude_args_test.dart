// claude_args_test.dart — buildClaudeArgs' tool grant.
//
// Every step is read-only, so its spawned `claude` call must carry
// --allowedTools and must never carry --dangerously-skip-permissions.

import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

void main() {
  group('buildClaudeArgs', () {
    test('read-only step: carries the allowlist, not the skip flag', () {
      final args = buildClaudeArgs(
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        sessionId: 'sess-1',
        toolGrant: ToolGrant.readOnly,
      );

      expect(args, contains('--allowedTools'));
      final idx = args.indexOf('--allowedTools');
      expect(args[idx + 1], equals('Read,Glob,Grep'));
      expect(args, isNot(contains('--dangerously-skip-permissions')));
    });
  });
}
