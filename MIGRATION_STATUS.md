# Migration effort — status, backlog, and handoff index

> Living summary of the fresh-machine-migration effort, started 2026-10-02.
> Not a design doc — see `README_PORTABILITY.md` for the public-facing
> discrepancy ledger and `docs/provider_setup.md` for provider specifics.
> This file exists so "what's done, what's active, what's parked" is
> answerable without re-reading the whole session. (Note: this file lives
> both on `main` and on the `fix/workspace-registry-onboarding` branch —
> they diverged once; this copy on `main` is the current one, since most
> work after PR #51 landed directly on `main`.)

---

## Closed out (2026-10-03) — migration effort complete

All three PRs below merged to `main` in all three repos. A final cold-cache,
fresh-clone, end-to-end pass (fresh `git clone` of all three repos, not a
warm existing checkout) by the second agent confirmed: `pub get` cold,
`analyze`, `test`, `custom_lint`, coverage floors, and native binary
compilation for both claudart and zedup all pass clean.

That first "fresh clone" pass surfaced 3 small, non-blocking issues, all
fixed directly to `main` and re-verified on a second genuine cold-cache
pass:
1. `zedup --version`/`--help` didn't work as standard flags — fixed in
   `zedup_router.dart` (claudart `f94f561`, zedup `f2f2add`).
2. `make check-coverage`'s error before `dart pub global activate coverage`
   was unhelpful (Dart's own bare "No active package coverage.") — both
   Makefiles now pre-check and fail fast (exit 2, under a second, no test
   suite run) with an actionable message.
3. zedup's `pubspec.lock` had a stale `claudart_lints` git ref (`3b827d0`)
   — refreshed to current (`5f340df`); confirmed cosmetic (lint package
   content was identical between the two revisions) before and after.

Final state verified cross-machine: claudart `f94f561` (1267 tests,
76.4%/74.0% floor), zedup `f2f2add` (2119 tests, 68.3%/66.0% floor),
dartrix `14cbc3e` (93 tests). No known gaps remain on either machine.

---

## Shipped (merged to `main`)

**PR [liitx/claudart#50](https://github.com/liitx/claudart/pull/50)** —
branch `feat/agent-provider-portability-harness`, 6 commits. Round-trip
tested against a real Bedrock-backed machine by a second agent — 2 real
bugs found and fixed, 1 real detection gap found and closed.
`AgentProvider`, `claude_settings_env.dart`, `claudart doctor`,
`PortabilityGap`, `README_PORTABILITY.md`.

**PR [liitx/claudart#51](https://github.com/liitx/claudart/pull/51)**
(stacked on #50) — split-brain workspace registry fixed (`workspacesRoot`
final→getter, `planner_log.dart`'s independent hardcode), `dartrix`→git
dependency, `CLAUDE.md`'s `PARADIGMS.md` pointer no longer hardcoded,
`claudart doctor` logs via `SessionLogger`, 3 new `HarnessCheckId` checks
(`workspaceRoot`/`registryHealth`/`pathConfiguration`). Round-trip tested
twice by the same second agent — first round found 3 real blind spots
(corrupt-registry vs. empty-registry indistinguishable, no folder-exists
check, no real split-brain detection against the `~/.claudart` fallback),
all fixed and re-confirmed. 1258 tests passing.

**zedup PR [liitx/zedup#76](https://github.com/liitx/zedup/pull/76)** —
same git-dependency fix (`dartrix`/`claudart`/`claudart_lints`, the last
via git+`path:` since it's a claudart subdirectory).

All three merged. zedup's `pubspec.lock` was upgraded (`dart pub upgrade
claudart dartrix`) and committed immediately after merging, per the action
item below — confirmed necessary since zedup's `claudart`/`dartrix` deps
are unpinned git dependencies that don't auto-update on merge.

**Test result discrepancy — resolved, real root cause, fixed.** The
second agent's 7 failures in `test/features/dashboard/zedup_dashboard_grid_test.dart`
were real and reproducible on a genuinely fresh clone — the discrepancy
with this machine's 52/52 pass was explained, not a flake. Root cause:
none of the file's 6 `AgentDispatcher(...)` constructions injected a
`versionGuard:` fake, so `AgentDispatcher`'s
`_versionGuard = versionGuard ?? ClaudartVersionGuard()` fell through to
a real `Process.runSync('claudart', ['--version'])` against whatever
happens to be on PATH. This machine has `claudart` compiled and
installed, so it accidentally passed; a machine without one (or CI)
reproducibly fails. Fixed by injecting the same `passingGuard()` fake
`agent_dispatcher_test.dart` already used correctly, at all 6 sites.
Verified the fix is genuinely hermetic, not coincidentally working: ran
the file with `claudart` stripped from `PATH` entirely — still 52/52.
zedup `main` at `0f3c434`.

---

## Shipped directly to `main` (not PRs — small, well-scoped, done headlessly)

1. **`CLAUDE.md`** — paradigm self-check made mandatory/unprompted in the
   Workflow protocol's Test step (direct user feedback: this should
   already be happening without being asked).
2. **Line-coverage floor** — claudart's `Makefile` gained `check-coverage`
   + `tool/check_coverage.dart` (dependency-free `lcov.info` parser, no
   new pub dependency). zedup had **no Makefile at all** — created one
   mirroring claudart's. Both floors set to each repo's own *measured*
   baseline (claudart 75.8, zedup 68.6), not a blind 100% target. zedup's
   `.gitignore` gained `coverage/` (was missing).
3. **`dartrix/PARADIGMS.md`** — new `architecture`-dimension bullet
   documenting why enums (not sealed classes) for matrix-tracked domain
   variants specifically — a real, named tradeoff (VGV's own published
   guidance picks sealed classes for data-isolated states), not a
   blanket rejection. Version 0.4.0 → 0.5.0.
4. **The off-by-one `knowledge/generic/` bug, fixed everywhere** — real,
   impactful bug: every project ever linked via `claudart link`/
   `claudart add` silently got an *empty* generic-knowledge-files list in
   its generated `CLAUDE.md`, because both call sites resolved
   `genericKnowledgeDirFor(workspace)` (per-project path) instead of the
   already-existing root-level `genericKnowledgeDir` getter — generic
   knowledge is shared/root-level, never per-project. Same root bug
   independently present in 4 command-template prose files
   (setup/suggest/debug/teardown — wrong path depth, and `suggest`/`debug`
   also named a file that's never existed, `dart.md` vs. the real
   `dart_flutter.md`) and in `claude_template.dart`'s own generated path
   string. `knowledge/projects/<name>.md` references were already
   correct (genuinely per-workspace) — left untouched. 6 new tests
   (these templates had zero prior coverage), 1233 total passing.

**Important correction, also recorded in memory:** earlier in this
session (and in a prior session's memory file), `bare_string_for_enum`
was repeatedly described as "inert" / "not implemented," based on
`dart analyze` reporting `'bare_string_for_enum' isn't a recognized
error code`. **This was wrong.** Verified directly by probe (a real
switch-on-string-literal fixture, run through `dart run custom_lint`
twice, once per repo): the rule fires correctly at ERROR severity. The
warning is cosmetic — the rule name is *also* listed under
`analyzer: errors:` in `analysis_options.yaml` (both claudart's and
zedup's), which sets real severity for custom_lint but isn't a code core
`dart analyze` recognizes on its own, hence the warning. Tested removing
that listing too: it silently drops severity to INFO — so the listing is
load-bearing, not dead weight; left untouched in both repos. The actual,
narrower gap: `bare_string_for_enum`'s real scope (switch-dispatch on
≥2 string-literal cases with an action) never covered plain duplicated
string-literal *values* (field initializers, map keys, function args)
outside that shape — which is what every real violation found this
session actually was. Manual verification is still genuinely necessary,
just for a narrower, correctly-understood reason now.

---

## Backlog — parked, not abandoned

> Note: `skills.md`/`handoff.md` (referenced below as "full detail") live
> in `~/dev/dev_tools/claude/claudart/`, which is **not a git repo** — it's
> local, this-machine-only session state, not visible to any other machine
> that only has this repo cloned. Item 1's full detail is reproduced here
> for that reason; item 2 genuinely has no further detail anywhere.

1. **Big architecture-shape decision.** Per-workspace tool config +
   shared/isolated knowledge across claudart/zedup/dartrix. Four candidate
   shapes, all coexistable with today's registry, none chosen yet:
   - (a) **layered inheritance** (Cargo/Turborepo-style) — root defaults,
     workspace opts into overriding fields.
   - (b) **named pools** (VS Code profiles / git `includeIf`-style) — a
     workspace joins a shared pool or stays isolated.
   - (c) **explicit link edges** (direnv `source_env`-style) — read-only
     imports from named sibling workspaces.
   - (d) **committed manifest + machine-local trust-gated overlay**
     (devcontainer.json / Claude Code settings.json-style) — the one shape
     that makes a fresh clone describe its own config.

   User's explicit standard: optimize for performance and native fit to
   claudart's existing dartrix-enum paradigm, not for adopting a named
   tool's mechanism wholesale — no new external dependency. Required
   deliverables for whichever shape wins (confirmed by the user, not
   negotiable):
   - `ZedProfile`'s hardcoded identity data
     (`zedup/lib/src/enums/zed_profile.dart:22-46`) AND its
     `configDir`→`tasks.json` mapping (`zedup_router.dart:456-473`'s
     `_defaultLauncher`) move to user-addable config without losing
     compile-time exhaustiveness.
   - Users can add their own custom scripts via zedup's TUI settings page
     (IDE-local vs. project-local scope explicitly decided as part of the
     recommendation).
   - A global searchable settings UI in zedup's TUI (fuzzy/text search
     across all settings, not a static scrollable page).
   - Workspace-to-workspace tool/task sharing, using the same mechanism as
     knowledge sharing, not a separate one.

   The other agent (Bedrock-backed, second machine) already gave an
   independent opinion when asked directly, unprompted to dig deep:
   1. Move `ZedProfile` to data — profile files under
      `~/.config/zedup/profiles/`, enum invariants enforced on load, not
      compiled constants.
   2. Don't duplicate git identity in that data — point each profile at a
      folder or a `git config include` instead of reimplementing
      credential logic.
   3. `githubOwners` must be data too — and flagged a real, concrete bug
      while reviewing it: Toyota's set was missing `arene-cockpit-sdk`.
      **Verified and fixed** — the Toyota account is a member of both
      `digital-cockpit` and `arene-cockpit-sdk`; zedup `main` now lists all
      three owners for Toyota (`aksana-buster-2_stargate`,
      `digital-cockpit`, `arene-cockpit-sdk`).
   4. Keep `AgentProvider` as its own setting, not strictly derived from
      the profile, though it can default per profile — the agent's own
      evidence: work-provided Bedrock access gets used from folders under
      the personal-default identity, so provider and identity aren't 1:1.
   5. Knowledge sharing isolated by default, profile as the hard boundary,
      sharing only inside one profile.
   6. A global → profile → workspace config cascade, plus a
      `zedup config show --origin` command showing where each resolved
      value actually came from — a debuggability feature none of the four
      shapes specified.

   (Note: the shape-(a)/(b) labels on points 5–6 above in an earlier
   version of this doc were this writer's own reading, not something the
   agent said — the agent gave this opinion before seeing the four
   named shapes. Corrected per the agent's own review.)

   The same agent also gave this quick lean on the four shapes, not a
   full evaluation:
   - Keep exhaustiveness by making the schema itself the enum — settings
     keys (type, default, scope, description) become the enum; profile
     and workspace instances become data maps keyed by it. Keeps
     compile-time exhaustiveness and gets the searchable settings UI and
     `config show --origin` almost for free.
   - Combine shapes: a cascade (a) for resolving values, profile as the
     sharing boundary (b), explicit link edges (c) for workspace-to-
     workspace tool sharing limited to within one profile.
   - Shape (d) directly addresses the problem this round's `skills.md`
     mixup just surfaced — state living outside the repo, invisible on
     another machine. The committed layer should hold only non-sensitive
     config; identity (emails, keys, accounts) stays in a machine-local
     overlay; committed scripts should be trust-gated before they run.
   - No new dependency needed — `dart:convert` covers the file format.

2. **Backup/restore + version-aware binary safety** — `claudart link
   --backup`. Not yet scoped past the name; no handoff, no design notes
   exist anywhere for this one yet.
3. **Golden/snapshot testing for zedup — mostly resolved, not actually a
   gap.** Research confirmed: nocterm (zedup's TUI framework) already
   ships a real snapshot-testing primitive —
   `testNocterm`/`tester.toSnapshot()`/`matchesSnapshot()`
   (`package:nocterm/nocterm_test.dart`) — and zedup already uses it
   extensively (18+ test files, one `testNocterm` case per FSM
   state/pane). `golden_toolkit` (the Flutter package the VGV comparison
   and `knowledge/generic/testing.md` both named) genuinely doesn't apply
   — but nocterm's own equivalent already exists and is in active use, so
   there was no real gap here, just an assumption that needed checking
   before acting on it. The one thing VGV's convention has that nocterm
   doesn't: a `GoldenTestGroup`-style bundling of multiple states into one
   reviewable artifact (nocterm only does pass/fail string equality per
   case) — optional nice-to-have, not foundational, not currently planned.

---

## What the other agent (Bedrock-backed, second machine) can do next

The migration/portability effort itself is closed — no outstanding test or
verification work queued for it. Open-ended, whenever picked back up:
1. Their independent take on the architecture-shape decision (Backlog
   item 1 above) — they've been a sharp, thorough independent reviewer
   all session.
2. Backup/restore design (Backlog item 2).
