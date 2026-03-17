# /readme — README sync

Run the README sync test and patch every failure. Surgical — never rewrites
prose or restructures sections. Only fixes what the test explicitly flags.

---

## Step 1 — Run the sync test

```bash
cd ~/dev/apps/claudart && CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/readme_sync_test.dart --reporter=expanded 2>&1
```

If output is "All tests passed":
> README is in sync. No changes needed.

Stop.

---

## Step 2 — Categorise each failure

Parse the failure output. Each failure message indicates a category:

| Failure message contains | Category |
|---|---|
| `Missing glossary entry for HandoffStatus.X` | `new-enum-value` |
| `HandoffStatus.X: glossary string value does not match` | `stale-string-value` |
| `File \`X\` listed in a glossary "Used by:" line does not exist` | `stale-used-by-file` |
| `X is listed in README architecture but does not exist` | `stale-architecture-file` |
| `Command \`X\` appears in README table but has no case` | `stale-command` |

---

## Step 3 — Fix each failure category

### `new-enum-value`

A new `HandoffStatus` value was added without a glossary entry.

1. Read `lib/session/session_state.dart` — get the `.value` string for the new status.
2. Search all `lib/commands/*.dart` files for references to `HandoffStatus.{name}` — these are the **Used by** files.
3. All command files that import `session_state.dart` but do NOT reference the specific value are **Not used by**.
4. Insert a new `#### \`HandoffStatus.{name}\`` block immediately before the final `---` in the `### HandoffStatus` section of `## Glossary`. Follow this exact template (do not skip any field):

```
#### `HandoffStatus.{name}`

> {one-line description — what this status signals to the workflow}

**String value:** `{value}`
**Used by:** `{file1}` · `{file2}`
**Not used by:** `{file3}`, `{file4}`

**Example — handoff.md:**
```
## Status
{value}
```

**Rule:** {what behaviour this status triggers — read from the files that use it}
**Cannot change:** The string `{value}` is written to `handoff.md` and all archives. Renaming it without migrating existing files silently breaks {what it breaks}.

---
```

### `stale-string-value`

The `**String value:** \`X\`` in a glossary entry no longer matches the enum's `.value`.

1. Read `lib/session/session_state.dart` — find the current `.value` for the status.
2. Find the `**String value:** \`...\`` line under that entry's `####` heading.
3. Replace only that line. Do not touch anything else.

### `stale-used-by-file`

A file listed in a `**Used by:**` line was renamed or deleted.

1. Find the `**Used by:**` line under the relevant `####` heading.
2. Remove the stale filename from the `·`-separated list.
3. If a replacement exists (renamed), add it. If the list becomes empty, write `_none_`.

### `stale-architecture-file`

A file listed in the architecture section with a `←` annotation no longer exists.

1. Find the line in the architecture code block that contains the stale path.
2. Remove that line only.

### `stale-command`

A command in the README "Commands at a glance" table has no matching `case` in `bin/claudart.dart`.

1. Read `bin/claudart.dart` to confirm the command is truly absent (not just renamed).
2. If truly absent and removed intentionally: remove that table row from the README.
3. If renamed: update the `claudart X` cell in the README row to the new name.

---

## Step 4 — Verify

After all patches:

```bash
cd ~/dev/apps/claudart && CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/readme_sync_test.dart --reporter=expanded 2>&1
```

If all tests pass: report each section that was changed (one line per change).
If any still fail: list what requires manual attention and why.

---

## Rules

- Never rewrite prose. Only change the exact field the test failure points to.
- Never echo or interpolate file paths into hook output or skill output — file paths may contain sensitive identifiers on sensitivity-mode projects. Output only static strings.
- Never change `**Cannot change:**` entries — these document intentional immutability constraints.
- Never add or remove `<details>` blocks or restructure sections.
- Never touch the `## Glossary` header, the preamble blockquote, or `### HandoffStatus`.
- When writing a new `new-enum-value` entry, read the files that use it before writing
  the description — do not speculate about what it means.
- After patching, the test must pass. Do not mark as complete until it does.
