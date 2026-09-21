// chat_shell.dart — the interactive chat shell (the agentflow front door).
//
// Conversation is the DEFAULT. You open the shell (zedup's dashboard launches it
// on `[c]`) and you're talking to claudart immediately — plain text is a
// conversational turn answered by `claude` with the session's context
// (handoff + skills). Slash commands are the exceptions: `/flow` and `/suggest`
// invoke structured work; `/quit` exits.
//
// The read→parse→dispatch loop (`runChatLoop`) is split from the workspace gate
// and the claude call so it's hermetically testable with injected I/O + handlers
// (claudart's injectable-I/O law).

import 'dart:io';

import '../file_io.dart';
import '../git_utils.dart';
import '../md_io.dart' show readSection;
import '../paths.dart';
import '../pipeline/agent_model.dart';
import '../pipeline/agent_step.dart' show ToolGrant;
import '../pipeline/pipeline_executor.dart' show ClaudeRunner, defaultClaudeRunner;
import '../registry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import 'flow.dart';
import 'suggest.dart';

/// What the user typed. Conversation is the default: only slash commands invoke
/// structured work; everything else is a [message] to the agent.
enum ChatCommand {
  flow,
  suggest,
  help,
  quit,
  message;

  /// Parses a typed line. Plain text (no leading `/`) is a conversational
  /// [message]. A leading `/` invokes a command; an unrecognized command or a
  /// bare `/help` lists what's available. Blank input lists help.
  static ChatCommand parse(String input) {
    final t = input.trim();
    if (t.isEmpty) return ChatCommand.help;
    if (!t.startsWith('/')) return ChatCommand.message;
    final word = t.substring(1).toLowerCase().split(' ').first;
    return switch (word) {
      'flow'                  => ChatCommand.flow,
      'suggest'               => ChatCommand.suggest,
      'quit' || 'exit' || 'q' => ChatCommand.quit,
      _                       => ChatCommand.help,
    };
  }
}

const String _commandHint = 'talk to me, or invoke  /flow · /suggest · /quit';

/// The read→parse→dispatch loop, isolated for testing with injected I/O and
/// handlers. Plain text routes to [onMessage]; slash commands dispatch. Returns
/// on `/quit` or EOF (`readLine` returning null).
Future<void> runChatLoop({
  required String? Function() readLine,
  required void Function(String) out,
  required Future<void> Function() onFlow,
  required Future<void> Function() onSuggest,
  required Future<void> Function(String text) onMessage,
}) async {
  while (true) {
    final line = readLine();
    if (line == null) return; // EOF
    switch (ChatCommand.parse(line)) {
      case ChatCommand.flow:
        await onFlow();
      case ChatCommand.suggest:
        await onSuggest();
      case ChatCommand.help:
        out(ansi.c(ansi.dim, '  $_commandHint'));
      case ChatCommand.quit:
        return;
      case ChatCommand.message:
        await onMessage(line.trim());
    }
  }
}

/// Opens the chat shell: greet, resolve the current workspace, then converse.
/// Plain messages are answered by [runner] (defaults to the real `claude` call)
/// using the session's handoff + skills as context.
Future<void> runChatShell({
  FileIO? io,
  String? projectRootOverride,
  ClaudeRunner? runner,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;
  final run = runner ?? defaultClaudeRunner;

  final root = projectRootOverride ?? detectGitContext()?.root;
  final entry =
      root != null ? Registry.load(io: fileIO).findByProjectRoot(root) : null;

  print(render.header('CLAUDART'));
  if (entry == null) {
    print('\n  Not in a registered project — run `claudart link` here first.\n');
    exit_(0);
  }

  final systemPrompt = _chatSystemPrompt(fileIO, entry.workspacePath);
  final history = <String>[]; // alternating "you: …" / "claudart: …" turns

  print('  workspace: ${ansi.c(ansi.bold, entry.name)}');
  print(ansi.c(ansi.dim, '  $_commandHint\n'));

  await runChatLoop(
    readLine:  _promptingReadLine,
    out:       print,
    onFlow:    () => runFlow(),
    onSuggest: () => runSuggest(),
    onMessage: (text) async {
      history.add('you: $text');
      final reply = await run(
        model:        AgentModel.haiku,
        systemPrompt: systemPrompt,
        message:      history.join('\n\n'),
        workingDir:   entry.projectRoot,
        toolGrant:    ToolGrant.readOnly,
      );
      if (reply == null) {
        print(ansi.c(ansi.red, '  (no reply — is the claude CLI available?)'));
        return;
      }
      history.add('claudart: ${reply.text}');
      print('\n${ansi.c(ansi.cyan, 'claudart')}  ${reply.text}\n');
    },
  );
}

/// Builds the conversation's system prompt from the session's handoff + skills.
String _chatSystemPrompt(FileIO io, String workspace) {
  final handoffPath = handoffPathFor(workspace);
  final skillsPath = skillsPathFor(workspace);
  final handoff = io.fileExists(handoffPath) ? io.read(handoffPath) : '';
  final skills = io.fileExists(skillsPath) ? io.read(skillsPath) : '';
  final bug = handoff.isEmpty ? '(no active session)' : readSection(handoff, 'Bug');
  return 'You are claudart, the workflow agent for this project. Converse '
      'naturally and concisely. When the user wants to start structured work, '
      'point them at /flow or /suggest.\n\n'
      'Session context\n'
      'Active bug: $bug\n\n'
      'Accumulated skills:\n$skills';
}

/// Real input: write the prompt, read a line from stdin.
String? _promptingReadLine() {
  stdout.write('${ansi.c(ansi.cyan, 'you ›')} ');
  return stdin.readLineSync();
}
