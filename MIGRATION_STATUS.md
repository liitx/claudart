# Migration effort — status, backlog, and handoff index

> Living summary of the fresh-machine-migration effort, started 2026-10-02.
> Not a design doc — see `README_PORTABILITY.md` for the public-facing
> discrepancy ledger and `docs/provider_setup.md` for provider specifics.
> This file exists so "what's done, what's active, what's parked" is
> answerable without re-reading the whole session.

---

## Shipped (merged-ready, not yet merged to `main`)

**PR [liitx/claudart#50](https://github.com/liitx/claudart/pull/50)** —
branch `feat/agent-provider-portability-harness`, 6 commits
(`d6cff0b`..`297ee03`). Round-trip tested against a real Bedrock-backed
machine by a second agent — 2 real bugs found and fixed, 1 real
detection gap found and closed.

- `AgentProvider` (`lib/providers/agent_provider.dart`) — apiKey/bedrock/openRouter
  detection from an env map.
- `claude_settings_env.dart` (`lib/providers/`) — reads `~/.claude/settings.json`'s
  own `env` block so detection isn't blind to config that never touches
  the shell.
- `claudart doctor` (`lib/commands/doctor.dart`, `lib/harness/harness_check.dart`) —
  fresh-machine verification harness: tools-on-PATH, git identity, `gh`
  auth, provider env. One `[OK]`/`[SKIP]`/`[FAIL]` line per check.
- `PortabilityGap` (`lib/portability_gap.dart`) — typed gap ledger backing
  `README_PORTABILITY.md`'s table.
- `README_PORTABILITY.md` — fork of `README.md` carrying this whole
  effort's discrepancy ledger (Providers, Git identity across machines,
  Known portability gaps).
- `claudeTemplate`'s generated `CLAUDE.md` tail now includes the git
  identity-verification standing rule for every claudart-linked project.

---

## Active handoff (this is what `/suggest-claudart` or `/debug-claudart` will pick up right now)

**`/Users/aksana.buster/dev/dev_tools/claude/claudart/handoff.md`** —
status `ready-for-debug`. 5 concrete, already-root-caused fixes:

1. Split-brain workspace registry (`lib/paths.dart:30-38`'s top-level
   `final` + `lib/logging/planner_log.dart:141`'s independent hardcode) —
   **live bug on this machine right now**, two diverging registries.
2. `pubspec.yaml`'s `dartrix` dependency → switch to a git dependency
   (decided).
3. `CLAUDE.md:67` (the one genuinely-hardcoded path — corrected finding,
   lines 107/110/111 self-heal via `claudart link`).
4. Wire `claudart doctor`'s output into `SessionLogger.logInteraction`/`logError`
   (`lib/logging/logger.dart`) so runs are visible via `claudart report`
   instead of hand-pasted into chat.
5. Expand `doctor` with workspace-health checks (registry entries point
   to real paths, `CLAUDART_WORKSPACE` actually set, `~/bin` on PATH).

---

## Backlog — parked, not abandoned (full detail in `skills.md`'s `## Pending` section)

All three live in
`/Users/aksana.buster/dev/dev_tools/claude/claudart/skills.md`, dated
2026-10-02, in the order they were parked:

1. **Big architecture-shape research.** Four candidate shapes for
   per-workspace tool config + shared/isolated knowledge (layered
   inheritance / named pools / explicit link edges / committed-manifest-
   plus-overlay), produced by a background Opus research pass. Required
   deliverables once picked back up: `ZedProfile`'s identity data AND its
   `configDir`→`tasks.json` mapping moving to user-addable config without
   losing compile-time exhaustiveness; easy custom-script integration via
   zedup's TUI settings (IDE-local vs. project-local scoping still open);
   a global searchable settings UI in zedup's TUI; workspace-to-workspace
   tool/task sharing via the same mechanism as knowledge sharing. Also
   scoped: whether dartrix's `Dartrix(axes:, features:)` matrix can cover
   workspace-resolution testing without being an aggressive suite
   (candidate axes named; blocked on 3 testability issues shared with
   item 1 of the active handoff above).
2. **Backup/restore + version-aware binary safety** (this session's
   newest idea, not yet written into its own handoff — see below).

---

## Newest idea: `claudart link --backup` — cross-machine workspace backup/restore

Not yet a handoff. Grounded findings so far:

- **The compiled binary itself carries zero workspace state** — confirmed
  by reading `_compile()` (`bin/claudart.dart:198-224`) and `Makefile`'s
  `build` target: both are a plain `dart compile exe`, pure code, no
  embedded data. All workspace state is 100% on-disk under
  `$CLAUDART_WORKSPACE`, read at runtime. The binary side of "migration"
  is already solved (`claudart compile` works from any fresh clone); the
  real problem is transporting the workspace tree.
- **Proposed shape, confirmed as reasonable, with one real precedent to
  build on:** `claudart link --backup` checks for a backup matching the
  current workspace name and lets the user pick one, reusing
  `claudart resume`'s existing archive-index-loading pattern
  (`lib/commands/resume.dart`, `lib/workspace/workspace_index.dart`'s
  `loadIndex`) — note precisely: `resume.dart` already plumbs an
  injectable `pickFn: int Function(List<String>)` end-to-end but today
  only ever auto-picks the newest archive (`archives.first`) — presenting
  an actual multi-item picker UI for backups would be new, not copied
  wholesale.
- Backup contents = workspace tree (tar/zstd via subprocess, no new
  package dependency) + a manifest recording: claudart version
  (`lib/version.dart`), and the exporting machine's own `doctor` check
  results (`HarnessCheckId`/`HarnessCheckResult`) at backup time.
- Restore flow: unpack manifest first, re-run `doctor` locally on the
  target machine, diff the two check lists using the same typed
  vocabulary on both sides, walk the user through what's missing —
  *then* unpack the workspace tree, *then* gate any binary
  compile/reinstall on a version comparison before overwriting anything
  (reuse `_compile()`, don't reinvent it — same "surface the mismatch,
  don't fix silently" rule as the git-identity-verification work).
- **Relationship to the parked architecture-shape research (item 1
  above):** this doesn't need to wait for that decision, but the backup
  manifest's schema should be versioned/extensible rather than treated as
  final — once a shape is chosen, the manifest is where `ZedProfile` data,
  task-script config, and knowledge-sharing links would also need to
  travel. Building backup/restore now and the shape decision later risks
  a second manifest format if they're not kept compatible; worth a
  one-line note in whichever handoff builds this first.
- **Testing plan, per the user's explicit ask:** once built, this should
  go through the same rigor as PR #50 — real PR, real cross-machine test
  by a second agent on the Bedrock-backed machine, not just unit tests
  here.

Not yet written into `handoff.md` — the active handoff (priority
migration fixes, above) takes precedence per the user's own
re-sequencing decision this session.
