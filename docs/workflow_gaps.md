# Workflow gap audit

What was exercised, what failed, what this PR fixes, and what is deliberately
left open or unverified. Written so a reader on another machine can repeat
every check.

## Method

- A throwaway Dart project with one planted bug (`add(a, b) => a - b`) and a
  matching test, in its own git repo.
- An isolated workspace: `CLAUDART_WORKSPACE=<temp dir>`, so the real
  `~/.claudart` was never touched.
- A binary compiled from `main` (`a529397`), then from this branch.
- The real `claude` CLI on a Bedrock-backed macOS machine, so `suggest` and
  `debug` made real model calls (5 runs, about $0.18 in total).
- Three kinds of stdin: a real terminal was NOT available in the harness, so
  each command was run with (a) stdin closed (`</dev/null`), (b) an empty pipe
  (`printf '' |`), and (c) scripted answers piped in.

## Results by command

Every command that does not call a model or create GitHub issues, run from a
fresh scratch project under two stdin modes, with the binary from `main` and
the binary from this branch (`CRASH` = "Unhandled exception"; otherwise the
exit code). Non-zero exits that are expected in the scratch project
(`preflight` with no handoff, `doctor` with `~/bin` off `PATH`, `setup` and the
launcher with nothing to read) are identical on both binaries.

| Command | `main`, stdin `</dev/null` | `main`, empty pipe | this PR, `</dev/null` | this PR, empty pipe |
|---|---|---|---|---|
| `init` | **CRASH** | exit 0 | exit 0 | exit 0 |
| `link` | **CRASH** | exit 0 | exit 0 | exit 0 |
| `unlink` | exit 0 | exit 0 | exit 0 | exit 0 |
| `setup` | **CRASH** | exit 1 | exit 1 | exit 1 |
| `status` | exit 0 | exit 0 | exit 0 | exit 0 |
| `status --prompt` | exit 0 | exit 0 | exit 0 | exit 0 |
| `save` | exit 0 | exit 0 | exit 0 | exit 0 |
| `preflight debug` | exit 1 | exit 1 | exit 1 | exit 1 |
| `archives` | exit 0 | exit 0 | exit 0 | exit 0 |
| `scan` | exit 0 | exit 0 | exit 0 | exit 0 |
| `report` | exit 0 | exit 0 | exit 0 | exit 0 |
| `confirm-pending --clear` | exit 0 | exit 0 | exit 0 | exit 0 |
| `resume` | exit 0 | exit 0 | exit 0 | exit 0 |
| `kill` | **CRASH** | exit 0 | exit 0 | exit 0 |
| `teardown` | exit 0 | exit 0 | exit 0 | exit 0 |
| `rotate` | exit 0 | exit 0 | exit 0 | exit 0 |
| `chat` | exit 0 | exit 0 | exit 0 | exit 0 |
| `flow` | **CRASH** | exit 0 | exit 0 | exit 0 |
| `doctor` | exit 1 | exit 1 | exit 1 | exit 1 |
| `(launcher)` | **CRASH** | exit 1 | exit 1 | exit 1 |

On `main`, **six commands crash with closed stdin** (`init`, `link`, `setup`,
`kill`, `flow`, and the launcher), and `suggest` crashes at its review menu.
This PR removes every crash in both modes. The two model-calling commands were
run separately with scripted answers:

| Command | Result on `main` | Result with this PR |
|---|---|---|
| `suggest` | three model steps succeed, then a crash at the review menu with stdin closed | works with closed stdin (aborts cleanly at the menu) and with piped answers |
| `debug` | "No files listed in Scope" on `suggest`'s own output (G2); with an empty pipe it writes files (G3) | runs the whole pipeline; refuses to write without an explicit choice |

## Failures found and fixed in this PR

### G1. `/dev/null` is mistaken for a terminal and the prompt layer crashes

- **Symptom:** with stdin closed (`</dev/null`), `init`, `link`, `setup`, `kill`,
  `flow`, the launcher and `suggest` die with `Unhandled exception: StdinException: Error setting terminal echo
  mode ... errno = 19` (exit 255). In `suggest`, the "hide cursor" escape had
  already been printed and was never undone, so the user's terminal cursor
  stayed hidden.
- **Cause:** `readLine` and `arrowMenu` trust `stdin.hasTerminal`. On macOS Dart
  reports `true` for `/dev/null` (a character device), and the next
  `stdin.echoMode = false` throws. `_arrowSelect` also hid the cursor and set
  raw mode outside its `try/finally`.
- **Fix:** `canUseRawTerminal()` (`lib/ui/terminal_support.dart`) also probes the
  echo mode and treats a `StdinException` as "not a terminal"; both callers use
  it and fall back to line-based input. The raw-mode setup in `_arrowSelect`
  moved inside the `try`, so the cursor is always restored.
- **Guard:** `test/ui/terminal_support_test.dart` (injectable) and
  `test/ui/non_tty_stdin_test.dart`, which runs the real entrypoint with stdin
  from `/dev/null`. The second was confirmed to fail on the unfixed code with
  the exact original exception.

### G2. `suggest` writes scope files in a shape `debug` cannot read

- **Symptom:** after a successful `suggest`, `debug` stops with "No files listed
  in ## Scope / Files in play".
- **Cause:** a contract gap between a prompt and a parser. The suggest prompt
  (`lib/pipeline/flows/suggest_steps.dart`) only says "One bullet per file -
  path and what specifically needs to change", with no format. The parser
  (`parseScopeFiles`) required ``- `relative/path` - description``. The model
  wrote `- /abs/path/lib/calc.dart: On line 1, ...` (absolute, unquoted,
  colon). Whether `debug` works therefore depends on how the model happens to
  format the bullet.
- **Fix:** `parseScopeFiles` accepts `-` or `*` bullets with a backticked or
  plain path, separators `:` `-` en dash em dash or nothing, and absolute
  paths that are inside the project (also matched against the symlink-resolved
  root, because a subprocess reports `/private/tmp/x` where the user typed
  `/tmp/x`). Absolute paths outside the project are dropped. Unquoted names
  need a file extension, so prose like "No changes needed" or "N/A" is not read
  as a file. Backticked relative paths keep their old behaviour exactly.
- **Guard:** `test/md_io_scope_files_test.dart` (17 cases, including the exact
  line the model produced and a symlinked project root).

### G3. End of input silently approves a destructive menu choice

- **Symptom:** with stdin empty or closed, `debug` printed "Select (1-2) >" and
  then "1 file written": model-generated edits were applied to the user's file
  with no human decision. The same path exists today with an empty pipe
  (`printf '' | claudart debug`), reproduced on `main`'s binary with a hand-built
  handoff: exit 0 and the file changed. G1 had only hidden it for `/dev/null`,
  by crashing first, so fixing G1 alone would have widened it.
- **Cause:** the numbered fallback returned item 0 at end of input, and item 0 of
  the debug/suggest review menus is the affirmative action.
- **Fix:** `selectNumbered` reports "No input available ... Nothing was selected;
  aborting without making changes" and exits 1. Valid input is unchanged.
- **Guard:** `test/ui/menu_fallback_test.dart`. Verified live: the same run now
  exits 1 and `git diff` is empty; an explicit approval still writes.

## Behaviour changes to be aware of

- Any menu reached with closed stdin now exits 1 instead of taking the first
  option. The six real callers are the launcher, setup, suggest, the debug
  approval menu, flow, and teardown; every command takes an injectable picker,
  so no existing test depended on the old default.
- `debug` and `suggest` now work on scope lists the old parser rejected.

## Observed, not changed here

1. `rotate` with no terminal prints "proceeding without confirmation" and runs
   its build gate (`afterFixCommand`, default `make rebuild`). A comment calls
   this deliberate. **Decided:** require an explicit `--headless` (see
   "Decisions" below).
2. `confirm()` answers "no" at end of input, so `link` with closed stdin
   silently leaves sensitivity mode OFF. **Decided:** `--sensitive` /
   `--no-sensitive`, otherwise abort.
3. A backticked relative path containing `..` is accepted and acted on.
   **Verified on `main`:** a `..` entry in `### Files in play` made the model
   step read a file outside the project root, and that file's contents appear
   in the request/response trace. **Decided:** containment on by default, with
   an explicit `allowedScopeRoots` allowlist.
4. The default `make rebuild` gate fails for any project without that Makefile
   target, and the failure message does not mention `afterFixCommand`.
5. `claudart --debug` (or `CLAUDART_DEBUG=1`) writes per-step traces to
   `$CLAUDART_DEBUG_PATH` (default `/tmp/claudart_debug.log`): worth knowing it
   exists and that it records prompts and file contents.
6. Small writer nit: typing the same file twice in `setup` (for example
   `calc.dart, lib/calc.dart`) produces two identical bullets.

**Withdrawn claim.** An earlier draft of this document (and the PR
description) said `setup` stores the "files already in mind" answer as free
text that `parseScopeFiles` never reads. That was wrong: it came from a
hand-written fixture in `test/e2e_smoke_test.dart`, not from the real writer.
`setup` already writes ``- `path` - (user-provided)`` bullets (resolving bare
file names through a file finder), and `debug` accepts them. Verified by
running the real binary.

## Not exercised

- Any run on a real interactive terminal (the harness has none), so the
  arrow-key menu and the cursor-editing prompt were not tested by hand.
- `report --file-issue` (it files GitHub issues).
- `flow` and `chat` with real model turns, and a successful `rotate` build gate.
- Linux. The `/dev/null` behaviour was observed on macOS only.

## Decisions (agreed 2026-10-03)

Agreed by the audit author and the claudart maintainer's agent. The names were
confirmed by the maintainer's side. None of these are implemented in this PR;
items 1 to 4 go in a follow-up PR stacked on this one, item 6 after the
process-tree kill (PR #53) merges.

| # | Decision | Names / notes |
|---|---|---|
| 1 | Non-interactive `link` requires an explicit flag, otherwise aborts. End of input never silently picks the less-protected outcome. | `--sensitive` / `--no-sensitive` (a negatable pair, matching the existing bare-flag style) |
| 2 | Pin the suggest prompt's scope-bullet shape; keep the tolerant parser as defence in depth. | ``- `relative/path` - what to change``; measure the shapes before and after |
| 3 | Containment on by default; crossing the project root is an explicit opt-in. | `allowedScopeRoots: List<String>` in `config.json`, empty by default |
| 4 | `rotate` with no terminal must not proceed silently. | reuse `--headless` (`RunMode.headless`), no new `--yes` |
| 5 | ~~Fix the `setup` writer.~~ Not needed: it already writes bullets (see the withdrawn claim). Only the duplicate-bullet nit remains. | - |
| 6 | A generous per-step backstop for `claude` spawns, hard error, no retry in the first cut. Harness-first, because `defaultClaudeRunner` is the live launch path. | `stepTimeoutMinutes`, default about 15; depends on `ProcessRunner.runKillable` from PR #53 |
