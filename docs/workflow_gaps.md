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

## Observed, not changed (questions, not fixes)

These look intentional or are judgement calls, so they are listed for the
author instead of being changed here. See the "Open questions" below.

1. `rotate` with no terminal prints "proceeding without confirmation" and runs
   its build gate (`afterFixCommand`, default `make rebuild`). A comment calls
   this deliberate.
2. `confirm()` answers "no" at end of input, so `link` with closed stdin
   silently leaves sensitivity mode OFF.
3. `setup` stores the "files already in mind" answer as free text, and
   `parseScopeFiles` reads only bullet lines, so that text alone never satisfies
   `debug`. The old e2e fixture even writes `lib/md_io.dart, lib/ui/line_editor.dart`
   as one line.
4. A backticked relative path containing `..` is accepted and later read.
5. The default `make rebuild` gate fails for any project without that Makefile
   target; the message does not mention `afterFixCommand`.
6. `claudart --debug` (or `CLAUDART_DEBUG=1`) writes per-step traces to
   `$CLAUDART_DEBUG_PATH` (default `/tmp/claudart_debug.log`): worth knowing it
   exists and that it records prompts, which may include project content.

## Not exercised

- Any run on a real interactive terminal (the harness has none), so the
  arrow-key menu and the cursor-editing prompt were not tested by hand.
- `report --file-issue` (it files GitHub issues).
- `flow` and `chat` with real model turns, and a successful `rotate` build gate.
- Linux. The `/dev/null` behaviour was observed on macOS only.

## Open questions

Each is a place where this PR had to choose or where the behaviour might be
intended. Answers are needed before anyone changes them.

1. **EOF default.** Should a non-interactive run ever default an answer? Today
   `confirm()` means "no" and menus (after this PR) abort. Is "sensitivity mode
   OFF when there is no input" acceptable for `link`, or should `link` require a
   flag or abort?
2. **Prompt format.** Should the suggest prompt pin the bullet shape (for
   example ``- `relative/path` - what to change``)? The parser now tolerates
   the common shapes, but pinning it would make the output consistent. Its
   effect has not been measured across Haiku, Sonnet and Opus.
3. **`..` in scope paths.** Is reading outside the project root intentional (for
   monorepos), or should containment also apply to backticked relative paths?
4. **`rotate` without a terminal.** Keep "proceed without confirmation"? If so,
   should the gate command be shown before it runs?
5. **Free-text file lists from `setup`.** Should `parseScopeFiles` also read
   comma-separated or plain lines, or should `setup` write bullets?
6. **A spawn timeout for `claude` steps.** A run that never returns is currently
   possible. What is the longest legitimate step, so a timeout can be chosen?
