# Claudart's review of the refactor state, 2026-11-06

A real `claudart suggest` run in a throwaway workspace on a clone of commit `5baf2c6` (`CLAUDART_WORKSPACE` and the project both under `/tmp`), given `claudart_consult_2026-11-06.md`. The analysis below is its output, unedited. It stopped at the approve/refine/exit menu because stdin was closed, so nothing was saved to a handoff. Cost: $0.23. The assistant's check of each claim is in `docs/methodical_refactor.md`.

═════════════════════════════════════════

  ROOT CAUSE
  ──────────
    I read the brief and `docs/topology/gates.md` directly. The code-side checks below come from the file findings, and I did not re-read those files.

    **Claims that hold against the code and docs**
    - **Q3 (`HandoffStore`).** `lib/session/handoff_store.dart` has `apply` (86-90), `rewrite` (125-135) and `replace` (141-153), and `rewrite` refuses a status change. One catch: `replace` logs instead of publishing when no transition exists (141-153), so a write can bypass the bus.
    - **Q4 (`HandoffTransitionBus`).** The constructor wires `applyNext` and `onFailure` (22-37), and `react` validates `mayEmit` and `listenersFor` (57-77).
    - **Q5 (`runRecorded`).** `lib/commands/support/interaction_boundary.dart` 18-51 logs one row per run with `wireName`, outcome and `durationMs`. `withExitHook` plus try/catch (36-50) keep it to one row.
    - **R14.** `lib/commands/rotate.dart` calls `writeArchiveEntry` at 130-141, before the build gate at 142-153. `gates.md` row 13 shows `archive 2` both at the gate and after a failure, so a retry adds a third entry.
    - **R15.** Neither `_runVerificationCommand` (`debug.dart` 342-351) nor `_defaultBuild` (`rotate.dart` 230-241) returns or logs an exit code or output tail. Each helper returns only a bool or throws.
    - **Shared mechanism.** Only `debug.dart` and `rotate.dart` spell `shellExecutable` (`gates.md` 26), and both use the same `sh -c` constants. This matches the brief.
    - **Gates differ.** `debug`'s gate runs inside nested closures in `applyEditFiles` under `blockOnFailure`. `rotate`'s is a direct call in `runRotate` (`gates.md` 16-22).
      - A failing `debug` gate throws `fixVerificationFailed`, moves to `needsSuggest`, and drops the fix.
      - A failing `rotate` gate returns `buildFailed` with no move.

    **Claims that are wrong or imprecise**
    1. The Q11 row says "five-row matrix". `lib/session/closure_evidence.dart` 15-34 defines four `ClosureEvidence` values: `verified`, `confirmedBySuggest`, `debugUnrecorded`, `none`. Either the matrix counts a different axis, or the brief or the code is out of date. The brief should name the five rows.
    2. Q5 says "every command run leaves one row". R12 itself says commands that log their own interaction also get the boundary's row. That is two rows for those commands, so the claim holds only for commands that don't self-log.
    3. The R14 note says "archive index 1 entry, then 2". `gates.md` shows `archive 2` at the gate, so the two numbers describe different runs. The generated doc doesn't show the 1-to-2 growth, and a test should pin it.
    4. `debug.dart` 325-332 writes `disposition: verified` whenever a `verificationCommand` exists, not when it passed. This is correct only because a failure throws before that write. The invariant is implicit, so a future non-throwing failure path would record `verified` falsely.
    5. The brief says "Q4 reactions bound to the table", but `replace` has a log-only path when no transition exists (141-153). That path is an unproven gap.
    6. A headless `teardown` never reads `disposition` (`teardown.dart` 112-114, 204-206, 369-375). That conflicts with `closure_evidence.dart` 78-84, where only `verified` maps to `teardownAndArchive`. Two parts of the code disagree on what `done` means.

    **Recommendations on the three open decisions**
    1. **Gates: keep two keys and two positions, and consolidate only the runner.**
       - Reason: the questions differ (is the fix correct vs. does the rebuild succeed), the positions differ, and the failure effects differ. A single runner returning exit code and output tail, with logging, fixes R15 and removes the duplicated `shellExecutable` spelling in two files.
       - Data that would change it: users setting the same command for both keys, or a failing gate that needs identical recovery in both flows.
    2. **R14: archive only after the gate passes.**
       - Reason: a failing gate currently leaves the state unchanged but still writes an archive entry, so every retry duplicates it. Moving `writeArchiveEntry` after the gate makes a failure a no-op, as `gates.md` row 13 implies.
       - Data that would change it: a need to keep a record of failed rotations. In that case log the failure (with the R15 output) instead of archiving.
       - Check the archive-then-gate order for a crash between the gate and the archive write. That risk is small and recoverable by rerunning.
    3. **Headless `teardown` with disposition `done`: save a reminder and do not archive.**
       - Reason: `automaticClosureFor` already says only `verified` archives, and the brief says only verified evidence should update the workspace. Today's headless archive contradicts it.
       - Teardown should call `closureEvidenceOf` and `automaticClosureFor` instead of re-deriving from `status == debugComplete`.
       - Data that would change it: most real projects having no `verificationCommand`. Then reminders would pile up and `done` is effectively the normal end state, so you would add a user opt-in rather than archiving silently.

    **What the test trace should record**
    - Per test: id, the `SpecObligation` it names, the input, the expected value, the actual value, a pass/fail flag, and a timestamp and run id.
    - Merge these into the existing run diagram by run id, so each test appears next to the command rows it exercised.
    - Record the expected value before the code runs, so a test that just echoes the actual value is detectable.
    - Record the actual value from the code under test, not from a mock.
    - Record which logger rows the test caused, so a test's claimed outcome can be checked against what was logged.
    - `SpecObligation` is the right anchor, since it already links each obligation to a consulting symbol and named checks. Add a trace field to it instead of creating a parallel enum.
    - A caveat is that tests with no obligation have no anchor, so they need an explicit "unanchored" bucket.

  SCOPE FILES
  ───────────
    This is a review, so no file changes now. The follow-up changes the brief would lead to, if the owner accepts the recommendations, are:
    - `lib/commands/debug.dart` — replace `_runVerificationCommand` (342-351) with the shared runner that returns exit code and output tail and logs both (R15).
    - `lib/commands/rotate.dart` — replace `_defaultBuild` (230-241) with the shared runner, and move `writeArchiveEntry` (130-141) after the gate passes (142-153) (R14, R15).
    - `lib/commands/teardown.dart` — read the disposition through `closureEvidenceOf` and `automaticClosureFor` for the headless archive decision (112-114, 204-206).
    - `docs/topology/gates.md` — regenerate with `make topology` after any gate change.
    - `lib/session/closure_evidence.dart` — no change expected. Reconcile the brief's "five-row" claim against the four-value enum.

  MUST NOT TOUCH
  ──────────────
    - The `after` function, the transition table, and every `lib/` file during this review. The brief says explicitly not to change them.
    - The ticket flow, the Workspace Feature and the handoff type list (K1 to K7, H1 to H4, Q10), which wait on the owner.
    - `docs/topology/gates.md` by hand. It is generated, and a test fails if it drifts from the code.
    - `README.md`, which must not advertise unbuilt features.
    - Nothing is pushed.

  CONSTRAINTS
  ───────────
    - Review only. The recommendations are not to be implemented in this pass.
    - Follow `CLAUDE.md`'s Workflow protocol (Verify, Plan, Test, Confirm, Commit). Never push, and commit only when asked. Verify git identity before any commit.
    - Any later `lib/` change must pass `dart test` and keep the FSM transitions exhaustive.
    - Run `dart run custom_lint`, then grep touched files for repeated string and numeric literals (`custom_lint`'s bare-string rule is inert). Printed sentences go through `text/user_text.json` and the generated `UserText`.
    - Run `make mutation-test-changed` for the touched files. A surviving mutation in new code must be fixed before commit.
    - Spec sentences need tests that pin their exact words (T4), and each spec obligation needs a consulting symbol and named checks (T2, T3).
    - Do not create a parallel enum for the test trace. Extend `SpecObligation`.
    - Keep the state machine simple, with no abstractions beyond the shared gate runner.

────────────────────────────────────────────

