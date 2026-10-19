# Plan: claudart workspace

Written 2026-10-16 from a measured gap analysis (doctor, make consumer-check,
make ownership, the three repos' CLAUDE.md and hooks). Order is by dependency;
each step names its check.

## State now

- Branch refactor/typed-handoff-status pushed at 84c3de6; not merged. zedup
  depends on claudart's `main`, so none of the typed API below reaches it yet.
- doctor: all OK after `claudart link` (commandTemplates were stale).
- 2589 tests pass, coverage 85.8% (floor 74), custom_lint clean, mutation
  survivors only in untouched older code (logger.dart 20, status.dart 27).

Update (2026-10-18): step 2 is built on branch feat/claude-code-binding: `claudart
hook pre-edit`, `ClaudartArtifact.claudeSettings`, merged into `.claude/settings.json` by
`claudart link`, checked by doctor. Posture reuses `owner.strict` (advise by default,
deny when strict) instead of a new config field. The binary on PATH needs
`claudart compile` after the merge. zedup and dartrix get it by running link on a
branch (zedup 6, dartrix 4).

## Steps

1. **Merge the branch to main** (PR; owner opens or says go). Blocks every
   zedup step. Check: zedup's pub get resolves a claudart that exports
   `applyHandoffEvent`, `HandoffEvent`, `summarizeWorkspaces`, `selectProject`.
2. **Bind Claude Code to the workflow, as a generated artifact.** Add a fifth
   `ClaudartArtifact` (`claudeSettings`) that `claudart link` writes into a
   project's `.claude/settings.json`, so the binding is the same in every
   linked repo and `doctor` flags it when stale:
   - `env`: `CLAUDART_DEBUG=1` (debug mode for every claudart call Claude Code
     makes there; trace goes to /tmp/claudart_debug.log).
   - `PreToolUse` on `Edit|Write|MultiEdit` for source paths: runs
     `claudart --project <name> preflight debug`. Posture follows dartrix:
     `consider` (default) prints the active session status and the rule
     "implement through /debug, record through /save"; `enforce` (opt-in via
     `workspace.json` `session.enforceClaudartFlow`) exits 2 and blocks the edit
     when no session is ready-for-debug or debug-in-progress.
   - Check: a drift test per posture against the real hook command; doctor
     fails when the file is stale; matrix test over ClaudartArtifact variants.
3. **Raise the coverage floor** from 74 to about 84 and add the per-file check
   for the logic layers, naming the terminal/spawn files as exceptions.
4. **Layering restructure** (agent_protocol leaf; see design.md 9.8), as one
   mechanical change plus a test that scans imports for upward edges.
5. **Declared model facts**: decide whether `maxOutputTokens` follows the CLI's
   reported cap; capture sonnet and opus runs.
6. File the pre-existing mutation survivors as an issue.
