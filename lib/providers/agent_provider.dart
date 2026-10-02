// agent_provider.dart — which auth backend the `claude` subprocess uses
//
// claudart's `defaultClaudeRunner` (pipeline_executor.dart) spawns `claude`
// via `Process.start`, which inherits the parent environment by default —
// there was never anywhere claudart itself resolved or validated which
// provider that ambient environment actually belonged to. A Bedrock-only
// machine, a plain ANTHROPIC_API_KEY machine, and an OpenRouter-backed one
// all looked identical to claudart: it just launched `claude` and hoped.
//
// AgentProvider.detect() makes that explicit: given an environment map,
// which provider (if any) has what it needs, so a mismatch surfaces as a
// clear error before the subprocess ever starts instead of a mid-pipeline
// 401.
//
// OpenRouter note: `openRouter`'s env vars are the obvious/documented ones
// (`OPENROUTER_API_KEY`) but routing Claude Code's own CLI through
// OpenRouter has not been verified end-to-end against the real tool —
// treat this variant as scaffolding until that's confirmed, not a proven
// path.

enum AgentProvider {
  /// Direct Anthropic API — `ANTHROPIC_API_KEY` only.
  apiKey(requiredEnvVars: ['ANTHROPIC_API_KEY']),

  /// AWS Bedrock — `CLAUDE_CODE_USE_BEDROCK` flag plus an active AWS
  /// profile/session. `AWS_PROFILE` is the one claudart can check for
  /// directly; actual credential freshness (Britive/SSO session expiry)
  /// is outside claudart's reach and must be handled upstream.
  bedrock(requiredEnvVars: ['CLAUDE_CODE_USE_BEDROCK', 'AWS_PROFILE']),

  /// OpenRouter — unverified against the real `claude` CLI (see file doc).
  openRouter(requiredEnvVars: ['OPENROUTER_API_KEY']);

  const AgentProvider({required this.requiredEnvVars});

  /// Env var names this provider needs present (and non-empty) to be
  /// considered configured. Order matches how they'd be checked/reported.
  final List<String> requiredEnvVars;

  /// Which vars from [requiredEnvVars] are missing or empty in [env].
  List<String> missingFrom(Map<String, String> env) => [
        for (final name in requiredEnvVars)
          if ((env[name] ?? '').isEmpty) name,
      ];

  /// True when every required var is present and non-empty in [env].
  bool isSatisfiedBy(Map<String, String> env) => missingFrom(env).isEmpty;

  /// Resolves which provider [env] is configured for.
  ///
  /// `explicit` (typically a `CLAUDE_PROVIDER` env var or CLI flag) wins
  /// outright when given and valid, so a machine with more than one
  /// provider's vars present — e.g. testing Bedrock and apiKey side by
  /// side — isn't left to guesswork. Otherwise the first variant (in
  /// declaration order above) whose required vars are all present wins.
  /// Returns `null` when nothing matches.
  static AgentProvider? detect(
    Map<String, String> env, {
    AgentProvider? explicit,
  }) {
    if (explicit != null) return explicit;
    for (final provider in AgentProvider.values) {
      if (provider.isSatisfiedBy(env)) return provider;
    }
    return null;
  }
}
