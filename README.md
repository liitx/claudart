# claudart_cli

A Dart CLI for managing structured debug and suggestion sessions during software development.

`claudart_cli` is a **Dart package** — not a Claude product. It manages session state via local markdown files (handoff, skills, archive) that coordinate between a suggestion agent and a debug agent in your editor. It has no opinions about your project structure; you point it at a workspace directory and it handles the rest.

---

## Concept

```
claudart_cli (Dart package)
      ↕  reads/writes
$CLAUDART_WORKSPACE/   ← your local workspace (project-specific)
  handoff.md           ← active session state
  skills.md            ← accumulated learnings
  archive/             ← past sessions
```

Your workspace holds the markdown files that your editor's AI agent commands read from and write to. `claudart` manages those files from the terminal — it does not run inside your editor.

---

## How the two parts work together

`claudart` and the slash commands (`/suggest`, `/debug`) are **separate tools** that share state through the workspace files.

```
Terminal                            Claude Code session (editor)
──────────────────────────────────  ────────────────────────────────────
claudart setup                      (writes handoff.md to workspace)
                                    /suggest  ← typed inside Claude Code
                                              reads handoff.md, explores
                                              writes KT back to handoff.md
                                    /debug    ← typed inside Claude Code
                                              reads handoff.md, fixes bug
                                              writes progress to handoff.md
claudart teardown                   (reads handoff.md, updates skills.md)
```

**`/suggest` and `/debug` are Claude Code slash commands** — they are defined as markdown files in your project under `.claude/commands/` and invoked by typing `/suggest` or `/debug` directly inside an active Claude Code session. They are not `claudart` subcommands and cannot be run from the terminal.

**`claudart`** runs only in the terminal. It sets up and tears down the session state those commands depend on.

---

## Dependency chain

```
claudart (global terminal command)
  └── activated from <path-to-claudart_cli>
        └── reads/writes $CLAUDART_WORKSPACE/

/suggest, /debug  (Claude Code slash commands)
  └── defined in <your-project>/.claude/commands/
        └── reads/writes $CLAUDART_WORKSPACE/
```

`claudart` requires two things. If either is missing it will break:

1. **Global activation** — must be activated via `dart pub global activate`
2. **`CLAUDART_WORKSPACE`** — must be set in your shell profile

---

## Install

Requires Dart SDK `^3.0.0`.

```bash
git clone https://github.com/liitx/claudart_cli <your-local-path>
cd <your-local-path>
dart pub get
dart pub global activate --source path <your-local-path>
```

---

## Configure your workspace

Set `CLAUDART_WORKSPACE` to wherever your local session files should live.
Defaults to `~/.claudart/` if not set.

```bash
# In your ~/.zshrc or ~/.bashrc
export CLAUDART_WORKSPACE=~/your/workspace/path
```

The workspace directory and its subdirectories are created automatically on first use.

---

## Usage

`claudart` commands run from the terminal. Run from inside your project directory so git branch detection works.

```bash
claudart setup [path]   # start a new session (path defaults to current directory)
claudart status         # check current session state
claudart teardown       # close session after bug is resolved
```

### setup `[path]`

Optional `path` argument — the project root used for git branch detection. Defaults to the current directory.

```bash
claudart setup                          # uses pwd
claudart setup ~/dev/apps/my-project    # explicit path
```

Reads accumulated skills, then prompts:

1. What is the bug? (actual behavior)
2. What should be happening? (expected behavior)
3. Any files already in mind? *(optional)*
4. Any BLoC events, provider names, or API calls involved? *(optional)*

Writes a structured `handoff.md` to `$CLAUDART_WORKSPACE`. Once written, open your Claude Code session and run `/suggest` or `/debug`.

### status

Prints current session state — status, bug summary, what's unresolved — and tells you which slash command to run next inside Claude Code.

### teardown

Run from the terminal after the bug is confirmed resolved. Prompts you to categorize the session, then:

- Updates `skills.md` with generic patterns (hot paths, root cause, anti-patterns)
- Archives `handoff.md` to `archive/`
- Resets `handoff.md` to blank template
- Drafts a commit message

---

## File layout

```
<your-local-path>/          ← the Dart package (generic, no project paths)
  bin/claudart.dart         ← CLI entry point
  lib/
    commands/
      setup.dart
      status.dart
      teardown.dart
    handoff_template.dart
    md_io.dart
    paths.dart              ← resolves workspace from CLAUDART_WORKSPACE

$CLAUDART_WORKSPACE/        ← your local workspace (not part of this package)
  handoff.md                ← active session state (shared between claudart and slash commands)
  skills.md                 ← accumulated learnings across sessions
  archive/                  ← past handoffs (auto-created, keep gitignored)
```

---

## Editor slash command setup

The slash commands (`/suggest`, `/debug`, `/teardown`) are separate markdown files that live in your project, not in this package. They must be set up per project.

```
<your-project>/
  .claude/
    commands/
      suggest.md    ← Claude Code slash command: /suggest
      debug.md      ← Claude Code slash command: /debug
      teardown.md   ← Claude Code slash command: /teardown
  CLAUDE.md         ← project-level instructions for Claude Code
```

> **These files must never be committed to your project repo.** Add `.claude/` and `CLAUDE.md` to your project's `.gitignore`.

Each command file instructs the AI agent to read from `$CLAUDART_WORKSPACE/handoff.md` and `skills.md`. The agent does not run `claudart` — it reads and writes the markdown files directly.

---

## Workflow in practice

```bash
# Terminal — start session
cd <your-project>
claudart setup

# Claude Code session — explore the problem (typed inside Claude Code)
/suggest

# Claude Code session — fix the bug (typed inside Claude Code)
/debug

# Claude Code session — if debug hits a wall, hand back to suggest
/suggest

# Terminal — close session after bug resolved
claudart teardown
```

### What each part enforces

| Part | Where it runs | Reads | Writes |
|---|---|---|---|
| `claudart setup` | Terminal | skills.md | handoff.md |
| `/suggest` | Claude Code | skills.md, handoff.md | handoff.md (KT only when confident) |
| `/debug` | Claude Code | skills.md, handoff.md | handoff.md (progress summary) |
| `claudart teardown` | Terminal | handoff.md | skills.md |

---

## Adapting to other projects

1. Clone and globally activate `claudart_cli`
2. Set `CLAUDART_WORKSPACE` in your shell profile
3. Create `.claude/commands/suggest.md`, `debug.md`, `teardown.md` in your project pointing to `$CLAUDART_WORKSPACE`
4. Add `.claude/` and `CLAUDE.md` to your project's `.gitignore`
5. Run `claudart setup` from the project root

---

## License

MIT
