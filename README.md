# claudart

A Dart CLI for managing structured debug and suggestion sessions during software development.

`claudart_cli` is a **Dart package** — not a Claude product. It manages session state and accumulated knowledge via local markdown files that coordinate between a suggestion agent and a debug agent in your editor. It has no opinions about your project structure.

---

## Core concept: the workspace

Your workspace is a **persistent local knowledge base** that lives on your machine — not inside any project. Projects reference it via symlinks; they don't own it.

```
$CLAUDART_WORKSPACE/
  knowledge/
    generic/
      dart_flutter.md     ← generic best practices (version-tagged)
      bloc.md             ← BLoC patterns
      riverpod.md         ← Riverpod patterns
      testing.md          ← testing patterns
    projects/
      dc-flutter.md       ← dc-flutter specific context and patterns
      my-other-app.md     ← another project's knowledge
  handoff.md              ← current session state (reset each session)
  skills.md               ← cross-session index
  archive/                ← full session history
  .claude/
    commands/             ← suggest.md, debug.md, teardown.md
  CLAUDE.md               ← aggregator: declares which knowledge files to load
```

The workspace grows smarter with every session across every project. You never re-initialize it — you just link it to whichever project you're working in.

---

## How the two parts work together

`claudart` (terminal) and the slash commands (`/suggest`, `/debug`) are **separate tools** that share state through workspace files.

```
Terminal                            Claude Code session (editor)
──────────────────────────────────  ────────────────────────────────────
claudart init                       (one-time workspace setup)
claudart init --project dc-flutter  (one-time per project)
claudart link                       (symlinks workspace into project)

claudart setup                      (writes handoff.md)
                                    /suggest  ← typed inside Claude Code
                                              reads knowledge/ + handoff.md
                                              writes KT back to handoff.md
                                    /debug    ← typed inside Claude Code
                                              reads knowledge/ + handoff.md
                                              fixes bug, writes progress
claudart teardown                   (updates knowledge/, archives handoff)

claudart unlink                     (removes symlinks from project)
```

**`/suggest` and `/debug` are Claude Code slash commands** — defined as markdown files under `.claude/commands/` and invoked by typing them inside an active Claude Code session. They are not `claudart` subcommands and cannot be run from the terminal.

**`claudart`** runs only in the terminal. It manages the workspace files those commands depend on.

---

## Dependency chain

```
claudart (global terminal command)
  └── activated from <path-to-claudart_cli>
        └── reads/writes $CLAUDART_WORKSPACE/

/suggest, /debug  (Claude Code slash commands)
  └── symlinked from $CLAUDART_WORKSPACE/.claude/commands/
        └── reads/writes $CLAUDART_WORKSPACE/
```

`claudart` requires two things. If either is missing it will break:

1. **Global activation** — must be activated via `dart pub global activate`
2. **`CLAUDART_WORKSPACE`** — must be set in your shell profile

---

## Install

Requires Dart SDK `>=3.0.0`.

```bash
git clone https://github.com/liitx/claudart_cli <your-local-path>
cd <your-local-path>
dart pub get
dart compile exe bin/claudart.dart -o ~/bin/claudart
```

Make sure `~/bin` is on your `PATH` (add to `~/.zshrc` if needed):

```bash
export PATH=$HOME/bin:$PATH
```

Compiling to a native executable avoids the `Resolving dependencies...` noise that appears when using `dart pub global activate --source path`. After any code change, re-run the compile command.

---

## Configure your workspace

```bash
# In your ~/.zshrc or ~/.bashrc
export CLAUDART_WORKSPACE=~/your/workspace/path
```

The workspace directory is created automatically on first use.

---

## Usage

### Interactive launcher

Running `claudart` with no arguments starts the interactive launcher:

```
claudart
```

It will:
1. List all projects registered in your workspace (with a `(linked)` indicator if already linked)
2. Ask whether this is a new bug or an existing one
3. Route you into the appropriate workflow — linking the workspace if needed, then starting setup

This is the recommended entry point for starting any session.

---

### One-time setup

```bash
# Initialize the workspace with generic starter knowledge
claudart init

# Register a project
claudart init --project dc-flutter
```

`init` only needs to run once per workspace and once per project. After that the knowledge files persist and grow automatically.

---

### Starting a session

```bash
# From your project root — wire workspace into the project via symlinks
claudart link

# Start the session (prompts for bug context, writes handoff.md)
claudart setup
```

`claudart link` does three things:
- Reads the project's `pubspec.yaml` and extracts the `environment.sdk` and `flutter` constraints
- Embeds those constraints into the generated `CLAUDE.md` so Claude Code and the Dart analyzer are scoped to the project's actual targets
- Creates two symlinks in your project directory:
  - `CLAUDE.md` → `$CLAUDART_WORKSPACE/CLAUDE.md`
  - `.claude/` → `$CLAUDART_WORKSPACE/.claude/`

The project repo never contains these files — they are gitignored. The workspace owns them.

The generated `CLAUDE.md` will include a section like:

```markdown
## Environment

- Dart SDK: `^3.8.0`
- Flutter: `3.32.5`

Do not suggest APIs or syntax unavailable within these constraints.
```

This scopes every suggestion and code change to the project's actual SDK target.

---

### In your editor

Once `claudart setup` has written the handoff, open your Claude Code session and use the slash commands:

```
/suggest    ← explore the problem, build knowledge transfer
/debug      ← scoped fix using the handoff
/suggest    ← if debug hits a wall, hand back
```

These read from `$CLAUDART_WORKSPACE/knowledge/` and `handoff.md` automatically.

---

### Ending a session

```bash
# After bug is confirmed resolved — updates knowledge, archives handoff
claudart teardown

# Remove symlinks from project
claudart unlink
```

`teardown` prompts you to classify what was learned:
- **Generic** → written to `knowledge/generic/` (available to all future sessions across all projects)
- **Project-specific** → written to `knowledge/projects/<name>.md` (available to future sessions on that project)

---

### Subsequent sessions (workspace already has knowledge)

```bash
claudart               ← launcher picks up existing project, routes straight to setup
# or manually:
claudart link
claudart setup
# /suggest and /debug now start with accumulated context
```

No re-initialization needed. The workspace picks up where it left off.

---

## The continuous improvement loop

```
Session runs
    ↓
claudart teardown classifies learnings:
    ↓                              ↓
knowledge/generic/          knowledge/projects/<name>.md
(any project benefits)      (this project only)
    ↓
Next session: agents load richer knowledge automatically
```

Over time, `knowledge/generic/dart_flutter.md` becomes a version-aware reference for Dart/Flutter best practices built from real debugging sessions — not documentation, but actual patterns that caused and solved bugs.

---

## File layout

```
<your-local-path>/              ← the Dart package (generic, no project paths)
  bin/claudart.dart             ← CLI entry point + interactive launcher
  lib/
    commands/
      init.dart
      launch.dart               ← interactive launcher logic
      link.dart                 ← reads pubspec, creates symlinks
      unlink.dart
      setup.dart
      status.dart
      teardown.dart
      suggest_template.dart     ← /suggest slash command content
      debug_template.dart       ← /debug slash command content
      teardown_template.dart    ← /teardown slash command content
    handoff_template.dart
    knowledge_templates.dart    ← starter content + CLAUDE.md generator
    md_io.dart
    paths.dart                  ← resolves workspace from CLAUDART_WORKSPACE

$CLAUDART_WORKSPACE/            ← your persistent local workspace
  knowledge/
    generic/                    ← grows across all projects
    projects/                   ← grows per project
  handoff.md                    ← current session (reset each teardown)
  skills.md                     ← cross-session index
  archive/                      ← full session history
  .claude/commands/             ← symlinked into projects at link time
  CLAUDE.md                     ← symlinked into projects at link time
```

---

## Editor slash command setup

The slash commands live in the workspace, not in your project. `claudart link` symlinks them in at session time and `claudart unlink` removes them after.

Add these to your project's `.gitignore` as a safety net:

```
.claude/
CLAUDE.md
```

---

## Workflow protocol

Always follow this order:

1. **Verify** — read and understand current state
2. **Test** — run safely
3. **Confirm** — present result, wait for confirmation
4. **Commit** — only after confirmed

---

## Adapting to other projects

```bash
# One-time
claudart init
claudart init --project my-project

# Each session
cd ~/dev/my-project
claudart          ← interactive launcher handles the rest
```

---

## License

MIT
