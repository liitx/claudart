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
  earlier draft of this doc overstated Zed's role here. **Detection gap,
  now closed:** `claude` reads `~/.claude/settings.json` directly,
  independent of the parent process's environment, so bare
  `AgentProvider.detect(Platform.environment)` missed a Bedrock machine
  configured only there — confirmed as a real false negative during
  testing. [`AgentProvider.detectEffective`](../lib/providers/agent_provider.dart)
  merges `Platform.environment` with
  [`claude_settings_env.dart`](../lib/providers/claude_settings_env.dart)'s
  read of that file's own `env` block before detecting (process env wins
  on conflict), and `claudart doctor` uses it. **Confirmed end-to-end**:
  both the Bedrock shell (env live) and a clean new Terminal tab (nothing
  exported, proven by printing the shell's own vars first) now correctly
  report `[OK] provider env: bedrock configured`, reading the same
  `~/.claude/settings.json` `env` object `claude` itself reads. Three
  known, non-blocking limitations surfaced during that confirmation:
  1. **Precedence is an assumption, not a verified fact.** `detectEffective`
     has process env win over settings.json on a conflicting key — but
     whether the real `claude` CLI resolves the two the same way when both
     set the same variable differently is unverified. Only matters if they
     ever actually disagree.
  2. **"Configured" isn't "working" — now partially closed.** `claudart
     doctor` originally only reported whether the right env vars were
     present, not whether the underlying Britive/AWS session behind them
     was still valid. `HarnessCheckId.bedrockCredentialsPreflight` now
     runs a real, bounded (`AWS_EC2_METADATA_DISABLED`-independent,
     10s-timeout) `aws sts get-caller-identity` when Bedrock is the active
     provider, confirming credentials actually resolve — never prints the
     resolved account ID/ARN, only ok/fail. Still doesn't catch every
     failure mode (e.g. a session valid for `sts` but lacking Bedrock
     model-invoke permission specifically).
  3. Project-local `.claude/settings.json` overrides still aren't read —
     unchanged limitation, not new.

## OAuth/Bedrock coexistence — measured, not assumed

Direct cross-machine testing (`OAUTH-BEDROCK-FINAL-REPORT.md`, two
machines — one genuinely `claude.ai`-OAuth-logged-in, one Bedrock-only
behind a corporate VPN that blocks `claude.ai` outright) replaced several
assumptions in this doc with measured facts:

- **Storage.** OAuth credentials live in the macOS **Keychain**
  (`Claude Code-credentials`, plus a hash-suffixed variant per distinct
  `CLAUDE_CONFIG_DIR`), not a `.credentials.json` file — that path is
  Linux-only. `~/.claude.json`'s `oauthAccount` key holds account/org
  metadata only (uuid, email, org, billing, seat tier, etc.), never the
  token itself.
- **Precedence, confirmed both directions.** Setting
  `CLAUDE_CODE_USE_BEDROCK=1` while genuinely OAuth-logged-in instantly
  flips `claude auth status` to `third_party`/`bedrock`; removing it
  reverts to `claude.ai` immediately, with **no re-login required**. The
  two auth paths coexist independently — neither clobbers the other's
  stored state.
- **The real failure mode for a broken Bedrock profile is a stall, not an
  error — this is the bug `bedrockMetadataDisabled` exists to catch.**
  When no valid AWS credentials are found, the AWS SDK falls through to
  probing the EC2 instance metadata service
  (`169.254.169.254`) as a last resort. On a non-EC2 host that's not a
  fast refusal — measured at **740 seconds (~12.3 minutes)** before the
  same `Could not load AWS credentials` error that `AWS_EC2_METADATA_DISABLED=true`
  produces in under 2 seconds. A misconfigured Bedrock profile without
  this flag doesn't look like an error to someone watching, it looks
  exactly like a hang.
- **`claude auth status` is the authoritative, ground-truth detector** —
  more reliable than inferring the active provider from which env vars
  happen to be set, since it reflects what `claude` itself actually
  resolved. It prints JSON (`loggedIn`, `authMethod`, `apiProvider`) even
  when it exits 1 (nothing configured) — stdout must be read regardless
  of exit code. [`AgentProvider.detectFromAuthStatusJson`](../lib/providers/agent_provider.dart)
  parses it; `claudart doctor` prefers this over env-based
  `detectEffective` when gating the two Bedrock-specific checks above,
  falling back to env inference only if `claude auth status` itself is
  unavailable or unparseable.
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
