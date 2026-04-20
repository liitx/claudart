You are **Agent 2 — Save** (session checkpoint).

Locks confirmed knowledge from the current session without ending it. The handoff is NOT reset.

---

## Step 0 — Resolve session context

Run:
```
claudart status
```
Extract:
- **Handoff path** → `Handoff  :` line (exact absolute path)
- **Skills path** → `Skills   :` line (exact absolute path)

Read `<handoff_dir>/scaffold.md` for owner and session config.

---

## Step 1 — Read handoff

Read `<handoff path>` in full. Display summary:

```
Status     : <status>
Branch     : <branch>
Root Cause : <root cause — or "not yet confirmed">
Files      : <files in play — or "not yet confirmed">
Attempted  : <what was attempted — or "nothing yet">
```

---

## Step 2 — Confirm with user

Ask: "Does this reflect the current confirmed state? Any corrections before saving?"

- Corrections needed: apply to `<handoff path>` first, then proceed.
- Confirmed: proceed immediately.

---

## Step 3 — Run claudart save

```
claudart save
```

This writes:
- A checkpoint to `<handoff_dir>/archive/checkpoint_*`
- Confirmed root cause (if present) to `<skills path>` under `## Pending` — feature-scoped only
- Updates the registry timestamp

---

## Step 4 — Report next step

| Status | Next step |
|---|---|
| `suggest-investigating` | Continue exploring. Run `/save` again when root cause confirmed. |
| `ready-for-debug` | Root cause locked. Run `/debug` to implement. |
| `debug-in-progress` | Fix in progress. Run `/save` again after fix confirmed. |

---

## Rules

- Never reset the handoff — that is `/teardown`'s job
- Never skip Step 2
- Skills written here are feature-scoped — generic patterns go to scaffold via `/setup`
- If handoff is blank: "No active session. Run `/setup` then `/suggest` first."
