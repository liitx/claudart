# test_readme — README sync test

Owns: `README.md`, `test/readme_sync_test.dart`

Run when: `README.md` or `test/readme_sync_test.dart` is changed, or after any
`lib/commands/*.dart`, `lib/session/*.dart`, or `bin/claudart.dart` change that
adds or removes a command, enum value, or file.

---

## Step 1 — Run scoped test

```bash
CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/readme_sync_test.dart --reporter=expanded
```

All tests must pass before proceeding.

---

## Step 2 — Module rules

### 1:1 glossary coverage

Every `HandoffStatus` enum value in `lib/session/session_state.dart` must have
a corresponding `#### \`HandoffStatus.{name}\`` entry in `README.md → ## Glossary`.
Adding a new enum value without adding a glossary entry is a violation.

```
grep -n "HandoffStatus\." lib/session/session_state.dart | grep -v fromString | grep -v value | grep -v ":"
```

Cross-reference against glossary entries:
```
grep -n "#### \`HandoffStatus\." README.md
```

Count must match.

### String values are immutable

The `**String value:**` field in each glossary entry must exactly match the
string returned by the enum's `.value` getter. No paraphrasing or shortening.

Check:
```
grep -n "String value:" README.md
```

Each value must appear verbatim in `session_state.dart`'s `value` getter.

### Used by files must exist

Every file named in a `**Used by:**` line must exist under `lib/`. A renamed or
deleted file with a stale "Used by" entry is a violation.

### Architecture entries must exist

Every `.dart` path annotated with `←` in the architecture section must exist on
disk. A deleted file with a stale architecture entry is a violation.

### Command table must match dispatch

Every `claudart X` row in the "Commands at a glance" table must have a
corresponding `case 'X':` in `bin/claudart.dart`. A removed command with a
stale table row is a violation.

### /readme is the fix mechanism

If any rule above is violated, the correct response is to run `/readme` — not
to manually edit the README. `/readme` reads the sync test failures and patches
exactly what is wrong. Manual edits risk drifting from the test's expectations.

---

## Coverage table

| Scenario | Covered |
|---|---|
| New HandoffStatus value → missing glossary entry detected | ✓ |
| Glossary string value mismatch with enum .value | ✓ |
| Stale "Used by" file that no longer exists on disk | ✓ |
| Architecture section references deleted file | ✓ |
| Command table row with no matching case in bin/claudart.dart | ✓ |
| Architecture section empty (accidental deletion) | ✓ |
| HandoffStatus.unknown skipped in string value check | ✓ |
