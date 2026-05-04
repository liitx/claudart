String saveCommandTemplate(String workspacePath, String projectName) =>
    '''---
description: Checkpoint session — $projectName
---

''' +
    r'''You are running **/save** — the session checkpoint command.

Save locks in confirmed knowledge from the current session without ending it.
It writes a checkpoint snapshot, deposits confirmed facts into pending skills,
and updates the registry. The handoff is NOT reset. The session stays open.

---

## Step 1 — Read handoff.md

Read `''' +
    workspacePath +
    r'''/handoff.md` in full.

Display a summary to the user:

```
Status     : <status>
Branch     : <branch>
Root Cause : <root cause — or "not yet confirmed">
Files      : <files in play — or "not yet confirmed">
Attempted  : <what was attempted — or "nothing yet">
```

---

## Step 2 — Confirm with user

Ask: "Does this reflect the current confirmed state? Any corrections before
saving?"

- If corrections: apply them to `''' +
    workspacePath +
    r'''/handoff.md` first, then proceed.
- If confirmed as-is: proceed immediately.

---

## Step 3 — Run claudart save

```
claudart save
```

This writes:
- A checkpoint to `''' +
    workspacePath +
    r'''/archive/checkpoint_*`
- Confirmed root cause (if present) to `''' +
    workspacePath +
    r'''/skills.md` under `## Pending`
- Updates the registry timestamp

---

## Step 4 — Report and guide next step

After `claudart save` completes, tell the user what is next:

| Status                    | Next step                                        |
|---------------------------|--------------------------------------------------|
| `suggest-investigating`   | Continue exploring. Run `/save` when root cause confirmed. |
| `ready-for-debug`         | Root cause locked. Run `/debug` to implement the fix. |
| `debug-in-progress`       | Fix in progress. Run `/save` again after fix confirmed. |

---

## Rules

- Never reset the handoff — that is `/teardown`'s job.
- Never skip Step 2 — user must confirm state before checkpointing.
- If handoff is blank (no session started):
  > "No active session. Run `claudart setup` first."
- If root cause is not yet confirmed, the checkpoint is still written —
  but tell the user: "Skills pending not updated — root cause not yet confirmed."
''';
