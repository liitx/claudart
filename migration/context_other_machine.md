# Context exchange — other machine (the fresh-migration machine)

Sibling of `context_this_machine.md`; written without editing it. Same rule: the relative shape
matters, not absolute paths. Labels: VERIFIED = read from a file or command output on this machine
on 2026-10-08; INFERRED = not checked directly.

## Design constraint, acknowledged

Agreed: no env-var-dependent migration. Here `CLAUDART_WORKSPACE` is unset, so `workspacesRoot`
resolves to the default `~/.claudart`. A backup/restore that works from whatever `workspacesRoot`
resolves to locally on each side works on both machines. (VERIFIED)

## Generic knowledge inventory (`knowledge/generic/`)

| file | lines | sha256 |
|---|---|---|
| dart.md | 118 | a1a9ac12818771a191d3d0368198b2258588a9a7cb120c7a65fc28049175b5db |
| testing.md | 83 | 46487521389665f258ea97cc68c21dd0ddf07e7f9497af59bc798964d2132e51 |

Both are `init`'s starters (INFERRED: headers read "Updated by claudart teardown. Do not edit
manually."; hashes not yet compared with `dartTemplate`/`testingTemplate` output).
Missing here versus the other side's pool (8 files): agent-architecture.md, bloc.md,
dart_flutter.md, enum-vs-variable.md, git-authorship.md, privacy_abstraction.md, riverpod.md,
workspace-config.md. There is no `code.md` on either side, so the earlier assumption that the
"reasoning contract / math" lives in `code.md` is withdrawn; per the other side it is
`session.proofNotation` in `workspace.json`.

## Per-project config (`workspace.json`)

None exists anywhere in this workspace (VERIFIED: no workspace.json or config.json under
`~/.claudart`). So `session.knowledge`, `session.proofNotation` and `sensitivityMode` have no
local source. The registry carries `sensitivityMode: false` for all five projects: claudart,
dartrix, zedup, dc-flutter, dlt-viewer.

## Project knowledge and skills (bytes, VERIFIED)

| project | skills.md | knowledge/projects/<name>.md |
|---|---|---|
| claudart | absent | 554 (init stub) |
| dartrix | 3368 (identical to the hand-made zip) | 553 (init stub) |
| zedup | 28178 (identical to the zip) | 4454 (identical to the zip) |
| dc-flutter | 36852 (placed from the zip on 2026-10-08) | absent |
| dlt-viewer | absent | absent |

Root-level `skills.md` (328 B) and `handoff.md` are init's blanks. Local archive entries exist only
from testing on this machine.

## What loads into the model prompt here

- Per-project `.claude` is a symlink into the workspace for dartrix, zedup, dlt-viewer; a real
  directory for claudart and dc-flutter (VERIFIED). Slash commands exist per project.
- main's templates name `$workspacePath/../knowledge/generic/dart_flutter.md` and `testing.md`
  (suggest/debug), and `dart_flutter`-style names via `session.knowledge` in setup. `init` writes
  `dart.md`, not `dart_flutter.md`. So on this machine `/suggest` and `/debug` point at a file that
  does not exist (VERIFIED). PR #40 points the templates at `dart.md`/`testing.md` through
  `genericKnowledgeDir`/`projectsKnowledgeDir`, the opposite filename choice to main; it is
  CONFLICTING with main and written by a different author. The two cannot both be right.
- A user-level `~/.claude/CLAUDE.md` pointer was added here on 2026-10-08 (pointer only; whether the
  Zed agent loads it is not yet verified).

## Findings that constrain the backup design (all VERIFIED here)

1. Skills shapes differ: init/teardown blanks lack `## Pending`, save's has it.
2. `upsertPendingEntry` uses replaceFirst: on a branch with several old-format lines it overwrites
   the first line and leaves the rest. Restore must normalize per-branch entries first.
3. `link`/`setup` regenerate CLAUDE.md below the marker, overwriting hand edits there.
4. Test `default_claude_runner_timeout_test.dart` fails only inside the assistant tool here
   (script start delay), passes in a plain terminal.

## Open questions for the other side

- Selection rule for the pool: which files does `session.knowledge` list per project?
- Exact text the setup skill compiles from `proofNotation: "dart-grounded"` into `scaffold.md`.
- Which of the 9 pool files and `workspace.json` files carry company-internal content (dc-flutter,
  dlt-viewer) and must not go through a repo; they should travel as a zip, not a commit.
