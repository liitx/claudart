# Experiment 01 — First self-hosted session

**Date:** 2026-03-17
**Branch:** main
**Model:** Claude Sonnet 4.5
**Tester:** Aksana Buster

---

## Objective

Run claudart on itself for the first time. Verify the full workflow
(`claudart link` → `claudart setup` → `/suggest` → `/save` → `/debug` →
`claudart teardown`) against a real bug found during setup.

---

## Bug tested

`claudart link` crashed with an unhandled `PathExistsException` when run inside
the claudart repo, which already had a real `.claude/` directory instead of a
symlink.

---

## Setup issues encountered

| Issue | Root cause | Fixed? |
|---|---|---|
| `claudart link` crash (PathExistsException) | `createLink` called unconditionally without `dirExists` check | ✓ during session |
| `✗ No project linked` false positive in `setup.dart` | `linkExists` check misses real directories | todo #7 |
| `/suggest` pulled project context | No claudart-specific `suggest.md` in `.claude/commands/` | ✓ before session |
| Workspace path used dev_tools root | `CLAUDART_WORKSPACE` env var set to `~/dev/dev_tools/claude` | expected — not a bug |
| Question 4 in setup references BLoC/Riverpod | Prompt is claudart-specific | todo #8 |

---

## Session metrics

| Metric | Value |
|---|---|
| Files explored by /suggest | ~11 |
| Files explored by /debug | ~3 |
| Total tests after session | 346 |
| New tests added | 1 (link_test.dart — real directory scenario) |
| Skills.md entries written | 1 root cause pattern + 1 hot files entry |
| Session duration (approx) | ~15 min end to end |

---

## Workflow output

### `/suggest`
- Preflight: clean
- Read handoff + README + git diff
- Identified root cause from git diff (fix already in place)
- Identified missing test coverage
- Set status → `ready-for-debug`

### `/save`
- Read 1 file
- Confirmed state correctly
- Ran `claudart save` — checkpoint written, skills.md pending updated

### `/debug`
- Preflight: clean
- Read handoff + README + test_link.md
- Verified fix implementation at lines 104–110
- Added regression test: "skips symlink when .claude is a real directory"
- Updated test_link.md coverage table
- Ran scoped suite: 16/16 passed
- Ran full suite: 346/346 passed

### `claudart teardown`
- Skills written to skills.md
- Handoff archived
- Commit message suggested (verbose — see todo #13 for table UI improvement)

---

## Bugs found during experiment

1. **PathExistsException crash** — fixed during session
2. **False positive "No project linked"** — filed as todo #7
3. **BLoC question wording** — filed as todo #8
4. **Teardown prompts UX** — filed as todo #13 (table confirmation UI)
5. **Workspace templates not written when symlink skipped** — fixed before session

---

## Verdict

Workflow is functional end to end for self-hosting. Sensitivity mode working
(PathExistsException → Class:A in handoff). Token efficiency validated — ~14
total files read across full session for a targeted bug fix.

---

## Next experiment ideas

- Run on a fresh machine with no `CLAUDART_WORKSPACE` set
- Test with a project that has no `.gitignore`
- Test sensitivity mode token map growth across 3+ sessions
- Test `claudart kill` mid-session recovery
