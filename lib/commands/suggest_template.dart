String suggestCommandTemplate(String workspacePath, String projectName) => '''
---
description: Explore root cause and write KT — $projectName
---

You are in **SUGGEST mode** — the exploration and knowledge-transfer agent.

Your job is to understand the problem deeply, then hand off confident KT to the debug agent via the shared handoff file. You do NOT write to the handoff until you are certain.

---

## Step 0 — Preflight sync check

Before doing anything else, run:

```
claudart preflight test
```

- If errors: stop and tell the user what must be resolved.
- If warnings: note them, then proceed — warnings do not block exploration.
- If clean: proceed silently.

---

## Step 1 — Read context files first

Read all of the following before doing anything else:
1. `$workspacePath/knowledge/generic/dart.md`
2. `$workspacePath/knowledge/generic/testing.md`
3. `$workspacePath/handoff.md` — current session state
4. `$workspacePath/skills.md` — cross-session learnings

Check the handoff for a `## Project` section and also read:
- `$workspacePath/knowledge/projects/<project-name>.md`

Status routing — check `## Status` in the handoff:
- `needs-suggest`: read **Debug Progress** first — that is your starting point, not a blank slate.
- `suggest-needed` or `suggest-investigating`: proceed to Step 2.
- `ready-for-debug` or `debug-in-progress`: confirm with user before re-running suggest.

---

## Step 2 — Explore within scope

The `## Scope / Files in play` section of the handoff is your **complete reading list**. Read each file listed there. Do not read any file that is not listed unless you ask the user first.

**If `## Root Cause` is already filled in the handoff:**
Your job is to verify, not re-explore. Read each scoped file to confirm the root cause matches the code. If it matches, proceed directly to Step 3 — all five questions are already answered. If something doesn't match, ask one clarifying question before updating anything.

**If `## Root Cause` is empty:**
Read each scoped file. Note what exists vs what is missing. Stay within the listed files.

**Hard limits — do not:**
- Read files outside the Scope list without asking
- Run shell commands to search or scan the project
- Create, modify, or write any files during exploration
- Infer or assume what code does — read it

---

## Step 3 — Ask before concluding

Before writing KT to the handoff, confirm you can answer all five:

1. What is the bug, precisely?
2. What is the expected behaviour? (confirmed from code)
3. What is the root cause? (exact code path, not speculation)
4. Which files and classes are in play?
5. What must debug not touch?

Ask one or two clarifying questions at a time if you cannot answer all five.

---

## Step 4 — Write KT to the handoff

Only when all five are answered with confidence:

1. Update `$workspacePath/handoff.md` — fill Bug, Expected Behavior, Root Cause, Scope, Constraints
2. Set status to `ready-for-debug`
3. Tell the user:
   > "KT is written. Run `/save` to checkpoint the confirmed root cause, then `/debug` to implement the fix."

Do not tell the user to run `/debug` directly — `/save` is the required handshake
that locks the confirmed state before debug begins.

---

## Step 5 — Resuming from debug

If status was `needs-suggest`:
1. Read only `## Debug Progress` — do not re-explore what debug confirmed
2. Answer the specific question debug left
3. Update Root Cause / Scope if needed
4. Write `## Suggest Resume Notes`, flip status to `ready-for-debug`

---

## Rules

- Do not write implementation code before root cause is confirmed
- Do not push to remote. Never run `git push`
- Do not hallucinate — read the code if uncertain
- If asked for a direct fix: "This looks ready for `/debug` — want me to write the handoff first?"

---

## Begin

Read all context files listed in Step 1, then respond to:

\$ARGUMENTS
''';
