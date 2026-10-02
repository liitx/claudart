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
//
// Detection scope — `detect()` only ever reads a `Map<String, String>`
// you hand it; it has no opinion on where that map came from. Confirmed
// against a real Bedrock machine: Bedrock env vars can live ONLY in
// `~/.claude/settings.json`'s own `env` block, never exported to the
// parent shell at all — `claude` itself reads that file directly. Calling
// `detect(Platform.environment)` alone would miss that case entirely.
// Use [AgentProvider.detectEffective] instead wherever the answer needs
// to reflect what `claude` would actually see, not just this process's
// shell state — it merges `Platform.environment` with
// `claude_settings_env.dart`'s read of that file before detecting. Even
// `detectEffective` isn't exhaustive (settings.json's own search path,
// project-local overrides, etc. aren't modeled) — this is exactly why
// neither function is wired into gating any real launch.

import 'dart:io' show Platform;

import 'claude_settings_env.dart';
import '../file_io.dart';

enum AgentProvider {
  /// Direct Anthropic API — `ANTHROPIC_API_KEY` only.
  apiKey(requiredEnvVars: ['ANTHROPIC_API_KEY']),

  /// AWS Bedrock — `CLAUDE_CODE_USE_BEDROCK`, `AWS_PROFILE`/`AWS_REGION`,
  /// plus the three per-tier model vars Claude Code needs when the
  /// account only has an application inference profile (not direct model
  /// access) — confirmed against a real Bedrock machine: the narrower
  /// two-var list this enum shipped with originally was "too optimistic"
  /// and would under-report there. Exact `ANTHROPIC_DEFAULT_*_MODEL`
  /// suffixes assumed to mirror claudart's own haiku/sonnet/opus tiers
  /// (see `AgentModel`) — reconfirm the literal names against that
  /// machine if this ever needs to be exact rather than best-effort.
  /// Credential freshness (Britive/SSO session expiry via a
  /// `bedrock-auth` helper) is outside claudart's reach regardless.
  bedrock(requiredEnvVars: [
    'CLAUDE_CODE_USE_BEDROCK',
    'AWS_PROFILE',
    'AWS_REGION',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
  ]),

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

  /// Like [detect], but merges in `~/.claude/settings.json`'s own `env`
  /// block first — the same source `claude` itself reads — so a provider
  /// configured only there (never exported to the parent shell) is still
  /// detected. Confirmed end-to-end against a real Bedrock machine, both
  /// with the env live and from a clean shell with nothing exported.
  ///
  /// [processEnv] values win over settings.json's on conflict — this is
  /// an assumption, not verified against how `claude` itself resolves the
  /// same conflict, and only matters if the two ever actually disagree.
  /// Also note this reports a provider as *configured*, not *working* —
  /// it checks for the right env vars, not whether the credentials behind
  /// them (e.g. a Britive/AWS session) are still valid.
  ///
  /// [io]/[settingsPath] are injectable for tests; production defaults to
  /// `Platform.environment` and `~/.claude/settings.json`.
  static AgentProvider? detectEffective({
    Map<String, String>? processEnv,
    FileIO? io,
    String? settingsPath,
    AgentProvider? explicit,
  }) {
    final settingsEnv = readClaudeSettingsEnv(io: io, path: settingsPath);
    final merged = {...settingsEnv, ...(processEnv ?? Platform.environment)};
    return detect(merged, explicit: explicit);
  }
}
