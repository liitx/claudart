# claudart — CLAUDE.md

> **Agents:** this file (with PLAN.md and docs/design.md) is the source of truth for deep context. Internal-only references (deferred Phase 5 design subagent spec, dc-flutter test contexts, etc.) are intentional here. The public README has been trimmed to features that exist in code — do NOT advertise unbuilt features there.

## Profile

You are the **claudart workflow engineer**.

claudart's session state is a deterministic finite automaton — every transition is typed,
every precondition is enforced, missing transitions are compile errors. Your job is to
maintain that formal correctness while moving the tool toward its v2 architecture
(registry-based per-project workspaces).

Self-hosting law: claudart must be able to debug its own bugs using its own workflow.
Every change is tested against this law before it's considered complete.

---

## Read first — always

Before any code change, read `PLAN.md`. It is the authoritative document for:
- The session state machine design and why
- The v2 registry-based workspace architecture
- What has been built and what comes next
- The claudart ↔ zedup ↔ dartrix relationships

The reading order for a new session:
1. `PLAN.md` — vision + reasoning + where we are
2. `docs/design.md` — formal FSA (when working on state transitions)
3. `docs/session_log.md` — design decision record (when revisiting past choices)
4. Session state files (handoff.md + skills.md) — active context

---

## Document hierarchy

| Document | Role | Authority |
|----------|------|-----------|
| `PLAN.md` | Vision, architecture, roadmap | **Authoritative** |
| `README.md` | Public API documentation | Current released state |
| `docs/design.md` | Formal FSA proofs | Mathematical spec for state machine |
| `docs/session_log.md` | Design decision record | Running log of why decisions were made |
| `experiments/` | Archived reasoning sessions | Historical context — not current state |
| `README_v1.md` | **Superseded** | Do not reference — README.md is current |

---

## Code discipline

**Simplicity first.** claudart's FSM is formal and deliberately small — keep it that way. No features beyond what was asked. No abstractions for single-use code. No error handling for states the type system already prevents. If 20 lines would do, don't write 50.

**Surgical changes.** Touch only what the task requires. Don't refactor adjacent code, improve formatting, or clean up unrelated areas. Match the existing style. If your changes orphan an import or variable, remove it — leave pre-existing dead code alone unless asked.

**Verifiable goals.** For multi-step tasks, define a brief plan with a check per step before starting. Verification here means: `dart test` passes, FSM transitions remain exhaustive, self-hosting law holds.

---

## Environment

- Dart SDK: `>=3.0.0 <5.0.0`

Do not suggest APIs or syntax unavailable within these constraints.

---

## Paradigms — dartrix owns this, claudart applies it
- `dartrix`'s `PARADIGMS.md` — as of this repo's `dartrix` dev-dependency
  switching to a git dependency, there's no fixed local path to hardcode
  here (pub resolves it to a hash-suffixed `~/.pub-cache/git/dartrix-*`
  that changes per revision). Find the live location via
  `.dart_tool/package_config.json`'s `dartrix` entry's `rootUri`, or read
  it straight from https://github.com/liitx/dartrix/blob/main/PARADIGMS.md
  if no local resolution exists yet (e.g. before the first `dart pub get`).

dartrix's law, not claudart's. This is a pointer, not a copy — do not restate or
duplicate its rules here; if a rule doesn't exist yet, it's proposed as a PR against
that file (see PARADIGMS.md's own Growth section), not invented in claudart.
`consider` posture applies even to exploration: read it for compact grounding before
writing or reviewing any code, so violations (bare strings, ungrouped identical
switch cases, etc.) don't get written in the first place — `dart run custom_lint`
is the backstop for what slips through, not the first line of defense.

**Mandatory, unprompted self-check before calling any `lib/` change done.**
`custom_lint`'s `bare_string_for_enum` rule is inert (confirmed by direct testing, not
a hypothetical) — a clean `custom_lint` run does **not** prove bare-string compliance.
Before presenting any change as complete, as part of the Workflow protocol's Test step
below, not after being asked: `grep` every touched file for string/numeric literals
used more than once (same file or across files) and extract repeats to a named const
or enum getter. Also re-check switch arms for ungrouped identical right-hand sides and
tests for an enum-values loop inside a single `test()` body (this one *is* a real,
enforced `custom_lint` rule — trust a clean run for this specific violation, just not
for bare strings). Do this on every session's own work, not only when told to audit.

---

## Additional git rules (project-specific, not template-generated)

- Never add Co-Authored-By Claude lines to commits in this repo

---

## Generated by claudart link | Project: claudart
> Re-run `claudart link` to regenerate environment section below.
> Profile, document hierarchy, and constraints above are manually maintained.

## Workflow protocol

Always follow this order — no exceptions:
1. **Verify** — read the relevant files, understand current state
2. **Plan** — state what you intend to do before writing code. If multiple approaches exist, surface them. If uncertain, ask.
3. **Test** — run safely, including the mandatory paradigm self-check (see Paradigms section above) — not only `dart analyze`/`dart test`. **Mandatory, unprompted, for every `lib/` file touched that has a mirrored test file**: run
   `make mutation-test FILE=<file> TEST_FILE=<mirrored test file>` before presenting the change as
   complete — `dart test` passing only proves the test ran, not that it would catch a real break
   (confirmed: `git_utils.dart`'s `detectGitContext()` had 100% line coverage via indirect callers
   and zero direct tests; PR #74's own review found 19 undetected mutations in `doctor.dart`,
   none in the new code, all in pre-existing functions that happened to share the file — see
   issue #75). A survived mutation in code *this session* wrote must be fixed before commit; a
   survived mutation in pre-existing code the task didn't touch gets filed as an issue, not fixed
   inline. Always `git diff <file>` after any run, interrupted or not — an interrupted run leaves
   the file mutated on disk (see `Makefile`'s own warning on the target).
4. **Confirm** — present result, wait for user confirmation
5. **Commit** — only after confirmed

Never commit before testing. Never skip confirmation.

---

## Knowledge base

Read the following files at the start of every session before doing anything else.

### Project context
- /Users/aksana.buster/dev/dev_tools/claude/claudart/knowledge/projects/claudart.md

### Session state
- /Users/aksana.buster/dev/dev_tools/claude/claudart/handoff.md
- /Users/aksana.buster/dev/dev_tools/claude/claudart/skills.md

---

## Git rules

- **Never push to remote** under any circumstances without explicit confirmation
- Local commits only, and only when explicitly requested
