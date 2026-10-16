# Plan: zedup workspace

Gap analysis 2026-10-16. Branch fix/chat-bare-command-default-project is clean
of code changes; a stray tool/_tmp_headless_suggest.dart (untracked) and a
modified .DS_Store are noise to remove. 2122 tests pass; analyze reports 10.

## What fails (measured, `make consumer-check` in claudart)

- 4 of 16 lifecycle steps DISAGREE: after teardown, kill, setup+kill and an
  empty rotate claudart says noHandoff and zedup shows suggestInvestigating,
  because zedup reads the raw Status line, not `SessionState.effectiveStatus`.
- 2 raw status writers bypass the state machine and its transitions log:
  lib/pipeline/surface/debug_coordinator.dart:191 and
  lib/pipeline/surface/suggest_coordinator.dart:187.
- zedup's own CLAUDE.md has no claudart workflow protocol, knowledge base, or
  dartrix pointer, and the repo has no hooks: Claude Code in zedup is not bound
  to the claudart flow.
- zedup parses registry.json itself (dashboard) instead of `summarizeWorkspaces`.
- Duplicate error taxonomy; fixtures that hard-code the old model slug.

## Steps (blocked on claudart step 1: merge to main)

1. New branch from main. Bump claudart (pub upgrade); check `make
   consumer-check` still reports the same 4 + 2 (baseline).
2. Reader: show `effectiveStatus` everywhere a status is read. Check: the 4
   disagreements go to 0.
3. Writers: move both coordinators (and archive restore) onto
   `applyHandoffEvent`. Needs a `restored` event; check whether the debug
   coordinator's direct `debug-complete` is a move the table rejects, and amend
   design.md's table if so. Check: consumer-check's raw-writer scan reports 0.
4. Workspaces: replace the registry.json parsing with `summarizeWorkspaces` /
   `selectProject`. Check: deleting the parser leaves tests green.
5. Delete the redundant fixtures and the duplicate error taxonomy; read
   `AgentCompleted.models` in the workflow pane (intended vs observed model).
6. Bind Claude Code: `claudart link` on the branch (writes the CLAUDE.md tail,
   command files, and, after claudart step 2, the settings artifact). Note: link
   also writes lib/generated/dependency_config.g.dart into the project; review
   that diff before committing.
7. Remove tool/_tmp_headless_suggest.dart and the .DS_Store change.
