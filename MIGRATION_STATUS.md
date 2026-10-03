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

## Shipped #2 — PR [liitx/claudart#51](https://github.com/liitx/claudart/pull/51) (stacked on #50, not yet merged)

Branch `fix/workspace-registry-onboarding`, built from #50's tip (not
`main` — `main` was missing #50's 3 follow-up fixes). The handoff above
this section was `ready-for-debug` with zero open questions, so
implementation went straight through rather than waiting on a separate
`/debug-claudart` invocation. All 5 items shipped:

1. Split-brain workspace registry, fixed — `workspacesRoot`
   (`lib/paths.dart`) final → getter; `planner_log.dart`'s independent
   hardcode now resolves through the same path.
2. `pubspec.yaml`'s `dartrix` → git dependency.
3. `CLAUDE.md`'s `PARADIGMS.md` pointer no longer a fixed absolute path.
4. `claudart doctor` now logs every run via `SessionLogger`, visible
   through `claudart report`.
5. 3 new `HarnessCheckId` checks: `workspaceRoot`, `registryHealth`,
   `pathConfiguration`.

Caught and fixed mid-session: `'CLAUDART_WORKSPACE'` had become a bare
string duplicated across two files — extracted to a shared
`claudartWorkspaceEnvVar` const before committing, per a direct "are you
using best Dart practices?" check. `dart analyze` + `dart run
custom_lint` both clean, 1253 tests passing, real smoke-tested on this
machine (all 7 checks, confirmed logging into `claudart report`'s
output). Cross-machine test on the Bedrock machine not yet run for this
PR — requested in the PR body, same as #50's process.

**`/Users/aksana.buster/dev/dev_tools/claude/claudart/handoff.md`** is
now `debug-complete` — no active handoff queued. Next candidates: the
cross-machine test above, or formalizing the backup/restore idea below
into its own handoff.

Also found via a direct "are you using best Dart practices?" self-audit,
not caught by `custom_lint` (its `bare_string_for_enum` rule is inert —
has to be checked by hand): `'HOME'` duplicated across 4 files, `'git'`/`'gh'`
duplicated within `doctor.dart` itself, `'doctor'` spelled twice in one
function. All extracted to shared consts, pushed as a follow-up commit
on the same #51 branch.

---

## Shipped #3 — zedup PR [liitx/zedup#76](https://github.com/liitx/zedup/pull/76) (not yet merged)

The claudart↔zedup↔dartrix trio was asked directly: "are all the
packages 1:1?" Answer was no — zedup's own `pubspec.yaml` had the
*identical* class of bug just fixed in claudart's (`dartrix`/`claudart`/
`claudart_lints` were all local path deps, so a fresh clone of zedup
alone couldn't `dart pub get` without also cloning both siblings first).
Fixed the same way: all three switched to git dependencies
(`claudart_lints` via git + `path:`, since it's a subdirectory of the
claudart repo, not its own). Branch `fix/git-dependencies-not-path`,
committed separately from other pre-existing uncommitted work already
sitting in zedup's working tree (`context_router.dart`/
`zedup_dashboard.dart` — untouched, left exactly as found).

Verified: `dart pub get` resolves `dartrix`/`claudart` from GitHub's
`main` (intentionally — #50/#51 aren't merged there yet, so zedup
currently builds against pre-this-effort claudart), `dart analyze`
matches the pre-existing 10-issue baseline, 2116 tests passing.

**Still not 1:1 for zedup** — this fix only closes the fresh-clone
`pub get` blocker. `ZedProfile`'s hardcoded identities, `zedup setup`
rewriting its own committed source file, and the whole backup/restore
story are all still backlog, tracked in `skills.md`'s Pending section
(the parked architecture-shape research).

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
