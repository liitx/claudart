# Claudart review of the logging decisions (sandboxed suggest session)

Produced by claudart itself on 2026-10-27: a throwaway workspace, a copy of this repo, a real `claudart suggest` run (reader on haiku, reasoning on sonnet or opus). Unedited except for this header. The assistant's check of each claim is in docs/methodical_refactor.md.

## Root Cause

The findings list four "open decisions", but they are not the ones in the document. The decisions actually under review are at `docs/methodical_refactor.md:333-351`: (1) `suggest` from `debugComplete`, (2) the hook when `workspace.json` can't be read, (3) the `kill` rule, (4) `readyForDebug --fixApplied`, plus (5) moving Q7 to last. The placeholder section at `docs/methodical_refactor.md:440-529` adds the K7/S10 question: should `teardown` become legal from the converged statuses, or should a new status be added? Each one checked against the code:

1. **`suggest` from `debugComplete`: reject with a message.** Right, and the rejection already happens in code. `lib/session/session_state.dart:90-93` maps `debugComplete` + `saveConfirmedReady` to null. `lib/commands/suggest.dart:83-88` throws `InvalidHandoffTransitionException` before any model call. So the change is only the message text (what to run next), not a new cell.
   - Missing evidence: "two attempts in two days" (`docs/methodical_refactor.md:337`) is not tied to any log record. The logger is built at `lib/commands/suggest.dart:69`, before the throw at :84, but none of the files I read show the rejection reaching `logError` or `transitions.jsonl`.
   - Logging risk: rejected `suggest` attempts may not be recorded at all, so the data behind this decision can't be re-counted.

2. **Hook fails open and logs it.** Right, and already built. `lib/commands/hook.dart:140-158` catches `WorkspaceConfigUnreadableException`, calls `reportFailure(command: ClaudartCommand.hook.name, …)` and returns `false` (not strict).
   - Missing evidence: no hook test or replay is cited.
   - Logging risk: every edit while the config is corrupt calls `reportFailure` again (:151), so the log can flood. Nothing in the files read shows a cap or dedupe for this path.

3. **`kill` rule: warn first, make it illegal later.** The two-step order is right given `lib/session/session_state.dart:175-182`: `killed` is legal from every live status, including `debugComplete`. It also matches the experiment (8 of 9 real kills were from `debugComplete`, `docs/methodical_refactor.md:330`).
   - Logging risk the plan missed: `lib/commands/kill.dart:148-152` logs `killed` from `debugComplete` as a normal legal move through `logHandoffMove` (`lib/logging/logger.dart:182-193`). A warned kill and an unwarned kill look the same in `transitions.jsonl`. `kill` never calls `logInteraction`, so there is no record that the warning was shown or overridden. Without that, the later "make it illegal" step has no data to justify it.
   - Missing evidence: a replay of the 44 moves showing how many kills would hit the warning (8 from `debugComplete`) and what the user then did.
   - A second gap: `lib/commands/kill.dart:107-119` reads the handoff but never checks it for converged KT, so the owner's "kill only when not confirmed" rule (`docs/methodical_refactor.md:457`) can't be enforced or logged from the handoff yet.

4. **Keep `readyForDebug --fixApplied` as `debug`'s start check for now.** Right. `lib/session/session_state.dart:128-131` allows `readyForDebug`/`debugInProgress` to `debugComplete`. `lib/commands/debug.dart:133-134` uses it as a check before any model call. The experiment shows 24 lifecycle runs break without it (`docs/methodical_refactor.md:331`).
   - Missing evidence: `fixApplied` at `lib/commands/debug.dart:312-325` is applied without running tests or `afterFixCommand` and without recording an evidence kind. "Fix verified" (`lib/commands/teardown.dart:97-102`) actually means "fix written".
   - Logging risk: `transitions.jsonl` records `debugComplete` with nothing that says whether the fix was tested. H6 (`docs/methodical_refactor.md:432`) needs exactly that.

5. **Q7 to last.** Right on the measured numbers (`docs/methodical_refactor.md:328-329`).

6. **Placeholder: ending a session by knowledge transfer.** The structural finding is right. `tornDown` is legal only from `debugComplete` (`lib/session/session_state.dart:164-174`). There is no typed debug disposition on `SessionState` (`lib/session/session_state.dart:239-299`), and nothing records skipped or not-applicable.
   - Logging risk the plan missed: in interactive mode, `teardown` decides "resolved" with `confirm_` (`lib/commands/teardown.dart:101-103`). A user who answers yes from `readyForDebug` still archives, and `logHandoffMove` writes `tornDown` as `rejected: true` (`lib/logging/logger.dart:195-205`; call at `lib/commands/teardown.dart:335-341`). Those rejected lines have no `to` field.
     - The "Real-log replay" check (`docs/methodical_refactor.md:412`) must say how rejected lines count.
     - The `teardown` analyzer pipeline (`lib/commands/teardown.dart:145-155`) has no `logPipelineEvents` subscriber (S7), so a `teardown` run leaves no pipeline record. H6 would rely on that record.
   - Missing evidence: how many real `tornDown`/`reminderSaved` moves were logged as rejected, and from which statuses.

7. **D9.** `suggest` still applies `saveConfirmedReady` with no check that the root cause has converged (`lib/commands/suggest.dart:287-294`). A converged status can therefore hold an unconverged root cause. That breaks "Status follows content" (`docs/methodical_refactor.md:408`) and makes any status-based log misleading.

8. **Protection on read: not a real gap.** The findings flag that `readStepModelRecords` (`lib/logging/logger.dart:290-304`) reads without protection. Protection is applied at write time (`_safe` :260-261, `logError` :306-359), and the sweep at `docs/methodical_refactor.md:327` confirms the files on disk are clean. Reads need no protection.

## Scope

### Files in play
- `docs/methodical_refactor.md` — at :333-351, note that recommendations 1 and 2 are already built (`suggest.dart:83-88`, `hook.dart:140-158`). Add the missing evidence: a log record for rejected `suggest` runs, the kill-warning record, the evidence kind for `fixApplied`, and how rejected moves count in the replay check (:412).
- `lib/commands/kill.dart` — for step 1 of recommendation 3: print the warning when the status is `debugComplete` and record that it was shown or overridden (it has no `logInteraction` today, :148-152). Leave `HandoffEvent.killed` legal.
- `lib/commands/suggest.dart` — rejection message for `debugComplete` at :83-88 saying what to run next; make sure the rejection is logged through the logger already built at :69.
- `lib/commands/teardown.dart` — subscribe the analyzer pipeline (:145-155) to `logPipelineEvents` (S7). Note that the interactive `confirm_` at :103 can produce a rejected `tornDown` at :335-341.
- `lib/commands/hook.dart` — optional: cap repeated `reportFailure` calls at :151.
- `lib/session/session_state.dart` — no change until the owner decides K7/S10; a debug disposition and evidence kind would go next to `SessionState` (:239-299).
- `lib/logging/logger.dart` — no change needed to protection; `logHandoffMove` (:182-206) is the one path that writes rejected moves.

### Key entry points in play
- `runKill()` — `lib/commands/kill.dart:32-162`
- `suggest` start check — `lib/commands/suggest.dart:83-88`
- `runTeardown()` — `lib/commands/teardown.dart:28-356`
- `_strictOf()` — `lib/commands/hook.dart:144-159`
- `debug` start check — `lib/commands/debug.dart:133-135`; `fixApplied` write at :312-325
- `SessionLogger.forEntry()` — `lib/logging/logger.dart:93-116`
- `SessionLogger.logHandoffMove()` — `lib/logging/logger.dart:182-206`

### Classes / methods in play
- `HandoffStatus.after(HandoffEvent)` — `lib/session/session_state.dart:49-187`
- `SessionState`, `effectiveStatus` — `lib/session/session_state.dart:239-299`
- `SessionLogger`: `logInteraction` (:148-158), `logPipelineEvent` / `_safe` (:216-261), `logError` (:306-359), `_appendJsonl` (:421-443)
- `LogProtection`, `PlainLogging`, `AbstractedLogging`, `LabelOnlyLogging` — `lib/logging/log_protection.dart:18-75`
- `InvalidHandoffTransitionException` — thrown at `lib/commands/suggest.dart:84`, `lib/commands/debug.dart:134`
- `WorkspaceConfigUnreadableException` — caught at `lib/commands/hook.dart:150`
- `DebugExitKind` — `lib/commands/debug.dart:29-63`

### Must not touch
- The `killed` and `tornDown` cells in `lib/session/session_state.dart:164-186`: don't make `kill` illegal from `debugComplete` until verified-closure `teardown` (H6, Q11) exists.
- The `readyForDebug` + `fixApplied` cell (`lib/session/session_state.dart:128-131`): it stays `debug`'s start check until Q3.
- The fail-open return in `lib/commands/hook.dart:157`.
- The protection logic in `lib/logging/log_protection.dart` and the D12 factories in `lib/logging/logger.dart:93-116`; the sensitive-logs sweep depends on them.
- K5/K2 handoff types: `setup`/`flow` classification stays as it is until the owner decides (`docs/methodical_refactor.md:434-438`).
- The K7 disposition and S10 status choice: the owner decides (`docs/methodical_refactor.md:519-520`).

## Constraints

- Any new move or status must pass every check at `docs/methodical_refactor.md:403-413`: totality with no default arm, the real-log replay of 44 moves, and no growth in the count of `String` fields.
- New values (disposition, evidence kind, warning outcome) must be enums or sealed types built through a factory, not strings (`docs/methodical_refactor.md:370-387`).
- Free text that gets logged must go through `_protection` (`lib/logging/logger.dart:260-261`).
- Writes to the handoff go through `applyHandoffEvent`. Don't add new direct writes (S2/S3).
- Before calling it done: run `dart test`, grep touched `lib/` files for repeated literals, and run `make mutation-test-changed`.
- Note: the claude.ai connectors and the `plugin:greenlight:greenlight` MCP server need authorization (claude.ai connector settings or `claude mcp` / `/mcp` in an interactive session). They were not used and can't be used until then.

## Debug Progress

### What was attempted
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

