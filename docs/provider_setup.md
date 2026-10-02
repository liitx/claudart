# Provider setup — current state vs. target

claudart spawns the real `claude` CLI from `defaultClaudeRunner`
(`lib/pipeline/pipeline_executor.dart`) via `Process.start`, which
inherits the parent process's environment by default. Until
`AgentProvider` (`lib/providers/agent_provider.dart`) existed, nothing in
claudart itself resolved or validated *which* auth backend that ambient
environment actually belonged to — a Bedrock-only machine, a plain
`ANTHROPIC_API_KEY` machine, and an OpenRouter-backed one all looked
identical to claudart: it just launched `claude` and hoped.

## Current state (as of this writing)

- **Default / OAuth login** — most machines run `claude` logged in
  interactively; credentials live in `~/.claude`, read directly by the
  `claude` CLI itself. No env vars required, `AgentProvider.detect()`
  correctly returns `null` here — this is not an error case.
- **Bedrock** — the one machine actually running this way today has
  *zero* claudart- or zedup-side support. The entire auth chain
  (`AWS_PROFILE` → `pybritive-aws-cred-process` → Britive session → IAM
  role) is wired entirely in Zed editor's own `settings.json`
  (`agent_servers.claude-acp.env`), repeated there because Zed launched
  from the Dock doesn't inherit the shell's PATH/env at all. claudart has
  no visibility into any of this.
- **OpenRouter** — not used anywhere yet. `AgentProvider.openRouter`'s
  env var (`OPENROUTER_API_KEY`) is the obvious/documented one, but
  routing the real `claude` CLI through OpenRouter has **not been
  verified end-to-end**. Treat this variant as scaffolding, not a proven
  path, until that's confirmed against the actual tool.

## `AgentProvider` (lib/providers/agent_provider.dart)

A pure, testable primitive — given an environment map, which provider (if
any) is configured, and what's missing if it isn't:

```dart
AgentProvider.detect(Platform.environment); // → AgentProvider? 
AgentProvider.bedrock.missingFrom(env);      // → ['AWS_PROFILE']
```

Detection order: an explicit override (e.g. a future `CLAUDE_PROVIDER`
env var or CLI flag) always wins; otherwise the first variant whose
required vars are all present and non-empty wins, in declaration order
(`apiKey`, `bedrock`, `openRouter`).

**Deliberately not wired into `defaultClaudeRunner` yet.** The pipeline's
`claude` launch path is live and load-bearing; forcing provider
validation into it without a harness to verify the change end-to-end
first (the fresh-machine verification harness, tracked separately) risks
regressing a currently-working session over an unverified assumption.
This file is the primitive the harness will consume once it exists.

## Target

1. The fresh-machine verification harness (idempotent `[OK]/[SKIP]/[FAIL]`
   checks) calls `AgentProvider.detect()` against the real environment
   before attempting a `claude` session, surfacing a clear "missing
   AWS_PROFILE for bedrock" instead of a mid-pipeline 401.
2. zedup consumes the same `AgentProvider` type from `package:claudart`
   (same pattern it already uses for claudart's git-identity helpers),
   rather than inventing its own.
3. OpenRouter support gets verified for real against the `claude` CLI
   before anything depends on it.
