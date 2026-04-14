# backlog/

Features encountered during development that are relevant and intended but not yet ready
to implement. Each entry captures enough context to pick the work up in a future session.

A backlog entry is NOT a retirement. The code it references may still be active.
It is a signal that says: "this matters, we saw it, we are not ready, do not lose it."

---

## Process

Before adding a backlog entry:
1. Confirm the feature is genuinely relevant — not just a nice-to-have tangent
2. Confirm there is no current equivalent already built
3. Document enough context that a future session can resume without reconstruction

A backlog entry does NOT authorize removal of any existing code. If the existing
code is still active, it stays active until the backlog feature is implemented
and the existing code is retired per the `retired/` process.

---

## Template

Copy this for each new entry. Filename: `<feature_name>_backlog.md`

```markdown
# Backlog: <feature name>

**Identified in:** `<commit hash or session date>`
**Date:** YYYY-MM-DD
**Priority:** high / medium / low

## What it is

One paragraph describing the feature clearly enough that a future session
understands it without reading the surrounding conversation.

## Why it is not ready

What is blocking or deferring implementation right now.

## Existing code to preserve

Any active files that must NOT be deleted until this is implemented.
List them explicitly.

## Design notes

Any design decisions, constraints, or prior thinking captured here.
Leave this empty if nothing is known yet — do not speculate.

## Blocked by / depends on

Other backlog items, todos, or external dependencies that must land first.
```

---

## Log

| # | Feature | Identified in | Priority | Blocked by |
|---|---------|--------------|----------|------------|

_(no backlog entries yet)_
