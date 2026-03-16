String teardownCommandTemplate(String workspacePath) => '''
You are running **SESSION TEARDOWN**.

> Preferred: use the Dart CLI — `claudart teardown`
> Only use this slash command if you want to drive teardown interactively.

---

## Step 1 — Confirm resolution

Ask: "Is the bug confirmed resolved?"
If no: "Come back when resolved. Use `/debug` or `/suggest` to continue."

---

## Step 2 — Read session files

Read both:
- `$workspacePath/handoff.md`
- `$workspacePath/skills.md`

---

## Step 3 — Classify learnings

For each learning from this session, decide:
- **Generic** → applies to any Dart/Flutter project → update `$workspacePath/knowledge/generic/`
- **Project-specific** → update `$workspacePath/knowledge/projects/<project>.md`

Write only patterns — no session-specific narrative.

---

## Step 4 — Update knowledge files

Generic learnings go to the appropriate file in `$workspacePath/knowledge/generic/`.
Project learnings go to `$workspacePath/knowledge/projects/<project>.md`.

---

## Step 5 — Archive and reset

- Archive handoff to `$workspacePath/archive/`
- Reset `$workspacePath/handoff.md` to blank template
- Update `$workspacePath/skills.md` session index

---

## Rules

- Never push to remote
- Generic patterns only in knowledge/ — no session noise
- Do not delete the archive

\$ARGUMENTS
''';
