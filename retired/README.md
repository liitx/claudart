# retired/

Artifacts retired from claudart. Nothing is silently deleted — every removal requires a
log entry here before the code is touched.

---

## Retirement process

Before removing anything:
1. Verify the artifact has no active consumers (`grep` the codebase)
2. Identify which commit(s) prove it is superseded or dead
3. Document the retirement using the template below
4. The retirement log and the physical deletion are **one atomic commit** — the log IS the deletion commit. If you are not ready to delete, do not create the log yet. No split commits. No exceptions. A log without a deletion, or a deletion without a log, means the retired/ directory no longer reflects reality and cannot be trusted.

---

## Template

Copy this for each new retirement. Filename: `<artifact_name>_retired.md`

```markdown
# Retired: <artifact name>

**Retired in:** `<commit hash>`
**Date:** YYYY-MM-DD

## What was removed

List of files / classes / dirs removed.

## Why

Reason the artifact is no longer needed. Be specific — reference the commit or feature
that made it redundant.

## What replaced it (if anything)

The replacement, or "nothing" with explanation.

## Key insight

One paragraph on what this retirement teaches about the design. This is the part
that gets promoted to dartrix or claudart's pattern library.
```

---

## Log

| # | Artifact | Retired in | Reason | Replacement |
|---|----------|-----------|--------|-------------|
| 1 | `AgentType` enum | _(pending)_ | Duplicated `AgentFlow` without model/step awareness | `AgentFlow` (extended with `hasCommandFile`, `commandTemplate`, `teardown`) |
