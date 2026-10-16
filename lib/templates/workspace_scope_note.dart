// workspace_scope_note.dart — the scope reminder every slash command carries.
//
// A session belongs to one workspace. The agent running it can learn that
// others exist (`claudart workspaces`) and how to reach one safely
// (`--project <name>`), instead of guessing paths or editing another handoff.
// One function, used by every command template, so the wording cannot drift.

String workspaceScopeNote(String projectName) =>
    '> **Scope:** this session is for the workspace **$projectName**. To see '
    'the other linked workspaces and where their sessions stand, run '
    '`claudart workspaces` (add `--json` for a machine-readable list). '
    'Never edit another workspace\'s `handoff.md` by hand; to work there, '
    'open its repo or pass `claudart --project <name> <command>`.';
