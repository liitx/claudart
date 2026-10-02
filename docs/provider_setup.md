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
- **Bedrock** — confirmed directly against the real Bedrock machine (via
  `claudart doctor`, run from the agent session with Bedrock env live):
  the actual chain is `~/.claude/settings.json`'s own `env` block →
  `~/.aws/config`'s `credential_process` (`pybritive`) → a Britive session
  that renews silently → an assumed IAM role, plus a `bedrock-auth` helper
  script for manual check/refresh. Zed editor's `settings.json` only
  **repeats** that same env block (because Zed launched from the Dock
  doesn't inherit the shell's PATH/env) — it does not own the chain, an
  earlier draft of this doc overstated Zed's role here. **Important
  detection gap:** `claude` reads `~/.claude/settings.json` directly,
  independent of the parent process's environment — `AgentProvider.detect`
  only ever sees `Platform.environment`. A terminal with no Bedrock vars
  exported can still mean a fully-working `claude` session; see
  `agent_provider.dart`'s own doc comment ("Detection scope") for the
  exact boundary. `claudart doctor`'s `providerEnv` check states this
  explicitly in its `[SKIP]` line rather than implying absence.
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
AgentProvider.bedrock.missingFrom(env);      // → ['AWS_REGION', 'ANTHROPIC_DEFAULT_HAIKU_MODEL', ...]
```

`bedrock`'s required vars were widened after testing against the real
machine: `CLAUDE_CODE_USE_BEDROCK` + `AWS_PROFILE` alone under-reported —
an account using an application inference profile (no direct model
access) also needs `AWS_REGION` and the three
`ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL` vars before `claude` will
actually work. The exact three model-var names are a best-effort guess
from Claude Code's documented tier naming, not a literal echo from the
test machine — reconfirm if this ever needs to be authoritative rather
than best-effort.

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
