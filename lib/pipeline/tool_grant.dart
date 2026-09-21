// tool_grant.dart — which tools a pipeline step's claude subprocess may use

/// Which tools a step's spawned `claude` process may use. Every current step
/// (reader, reasoner, planner, lookup, applier, categorize, clarify,
/// construct, the debug implementer, the chat turn) only emits text for the
/// caller to parse — none edits files or runs commands itself — so
/// [readOnly] is the only variant so far. Add a variant here, with its own
/// CLI args in `buildClaudeArgs`, the day a step needs more.
enum ToolGrant {
  /// Read-only: file reads and searches, nothing else.
  readOnly(tools: ['Read', 'Glob', 'Grep']);

  const ToolGrant({required this.tools});

  /// Value passed to the `--allowedTools` CLI flag (comma-joined).
  final List<String> tools;
}
