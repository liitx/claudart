# retired/

Artifacts retired from claudart. Nothing is silently deleted — every removal requires a
log entry here before the code is touched.

---

## Retirement process

Before removing anything:
1. Verify the artifact has no active consumers (`grep` the codebase)
2. Identify which commit(s) prove it is superseded or dead
3. Document the retirement using the template below
4. Commit the retirement log first, then remove the artifact in the same or next commit

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

_(no retirements yet — log entries added here as artifacts are retired)_
