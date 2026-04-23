# claudart

A Dart CLI that brings structured memory, session state, and privacy to your Claude Code workflow.

> Not an Anthropic product. Built for Claude Code + Dart/Flutter projects.

---

## What is claudart?

**claudart** is a compiled Dart CLI — a binary you run in your terminal. It manages everything *between* Claude Code sessions: writing structured context before you open your editor, checkpointing discoveries mid-session, protecting sensitive identifiers before they leave your machine, and extracting learnings when a session ends.

**Claude Code** is the AI assistant built into your editor — VS Code, Cursor, or any IDE with Claude integration. You interact with it through slash commands in the chat panel: `/suggest` to explore a bug, `/debug` to implement a fix, `/save` to lock confirmed knowledge. It reads the context claudart wrote, so every session starts already knowing the bug, the declared scope, and what has been tried.

The two tools are completely separate. They communicate through a single shared file — `handoff.md` — that lives on your machine and is never sent to Anthropic until Claude reads it (abstracted first, if sensitivity mode is on).

| | claudart | Claude Code |
|---|---|---|
| **What it is** | Dart CLI — compiled binary at `~/bin/claudart` | AI assistant built into your editor |
| **Where you use it** | Terminal | IDE chat panel |
| **What you type** | `claudart setup`, `claudart teardown` | `/setup`, `/suggest`, `/debug`, `/save` |
| **What it manages** | Session state, workspace config, skills, privacy | Workspace scaffold, exploration, fix implementation |
| **Runs on** | Your machine only (`~/.claudart/`) | Anthropic servers — reads your abstracted context |
| **IDE examples** | — | VS Code · Cursor · any Claude-integrated editor |

claudart operates as **two distinct agents**:

- **Agent 1 — `/setup`** runs once per workspace. Reads `workspace.json` (owner, stack, knowledge scope), compiles it into `scaffold.md` — a stable context file that every session inherits. Generic knowledge is baked in here, not re-read each session.
- **Agent 2 — `/suggest`, `/debug`, `/save`, `/teardown`** runs per feature or bug. Inherits `scaffold.md`, loads only `handoff.md` + `skills.md` + the one feature-scoped doc the handoff references. Context window stays narrow and task-specific.

---

## Quick start

```bash
# 1. Clone and compile
git clone https://github.com/liitx/claudart ~/dev/claudart
cd ~/dev/claudart
dart compile exe bin/claudart.dart -o ~/bin/claudart

# 2. Add ~/bin to PATH (if not already)
echo 'export PATH=$HOME/bin:$PATH' >> ~/.zshrc && source ~/.zshrc

# 3. Link your project
cd ~/dev/my-flutter-app
claudart link          # registers project, creates workspace, wires .claude symlink

# 4. Start a session
claudart setup
# → open your editor and type /suggest in the Claude Code chat panel
```

**Recompile after updates:**
```bash
dart compile exe ~/dev/claudart/bin/claudart.dart -o ~/bin/claudart
```

---

## How they work together

```mermaid
sequenceDiagram
    participant T  as claudart CLI (terminal)
    participant W  as workspace.json
    participant SF as scaffold.md
    participant IDE as IDE (VS Code · Cursor)
    participant C  as Claude Code
    participant H  as handoff.md
    participant S  as skills.md
    participant R  as README.md

    rect rgb(20, 40, 20)
        Note over T,SF: Once per workspace — Agent 1
        T->>W: claudart link — registers project, writes workspace.json
        IDE->>C: /setup
        C-->>W: reads owner · stack · role · knowledge scope
        C->>SF: compiles scaffold.md — owner · proof notation · summarised knowledge
    end

    rect rgb(20, 20, 50)
        Note over T,S: Per feature / bug — Agent 2
        T->>H: claudart setup — writes bug · scope · branch
        Note over T,IDE: open your editor

        IDE->>C: /suggest
        C-->>SF: inherits scaffold (owner · stack · patterns)
        C-->>H: reads session state
        C-->>S: reads feature-scoped learnings
        C->>C: explores codebase within declared scope
        C->>H: writes root cause — status → ready-for-debug
        C->>S: appends discovered pattern to Pending

        IDE->>C: /save
        C-->>H: checkpoint → archive/
        C->>S: confirms root cause in Pending

        IDE->>C: /debug
        C-->>SF: inherits scaffold
        C-->>H: preflight — status must be ready-for-debug ✓
        C->>H: status → debug-in-progress
        C->>C: implements scoped fix — minimal diff

        IDE->>C: /teardown
        C-->>H: reads · archives · resets
        C->>S: promotes feature learnings — Pending → Confirmed
        C->>R: updates README sections [only if role == maintainer]
    end
```

### claudart commands vs slash commands

| | Terminal — claudart | IDE chat panel — Claude Code |
|---|---|---|
| Configure workspace | `claudart link` + edit `workspace.json` | `/setup` — compiles scaffold once |
| Start session | `claudart setup` | — |
| Explore & diagnose | — | `/suggest` |
| Checkpoint | `claudart save` | `/save` (same operation) |
| Implement fix | — | `/debug` |
| End session | `claudart teardown` | `/teardown` — promotes skills, updates README if maintainer |
| Check state | `claudart status` | — |
| Abandon session | `claudart kill` | — |

> **`claudart` commands** run in your terminal. **`/setup`, `/suggest`, `/save`, `/debug`, `/teardown`** are slash commands — type them in the Claude Code chat panel inside your editor.

---

## The workflow

| Step | Command | Agent | Run in | What happens |
|---|---|---|---|---|
| 0 | `/setup` | Agent 1 | Claude Code | Reads `workspace.json`. Compiles `scaffold.md` — owner, stack, proof notation, knowledge. Run once per workspace, re-run when `workspace.json` changes. |
| 1 | `claudart setup` | — | Terminal | Describe the bug. claudart writes a structured `handoff.md` |
| 2 | `/suggest` | Agent 2 | Claude Code | Inherits `scaffold.md`. Loads `handoff.md` + `skills.md` only. Explores codebase. Confirms root cause. Status → `ready-for-debug` |
| 3 | `/save` | Agent 2 | Claude Code | Checkpoints handoff to `archive/`. Deposits root cause to `skills.md → Pending`. Session stays open |
| 4 | `/debug` | Agent 2 | Claude Code | Preflight check. Reads checkpointed handoff. Scoped fix — touches only what it declared |
| 5 | `/teardown` | Agent 2 | Claude Code | Promotes `skills.md` learnings. Updates `README.md` when `workspace.json` `role` is `maintainer`. Archives handoff. |

`/save` is the required handshake between `/suggest` and `/debug`. It is the lock that prevents `/debug` from operating on stale or unconfirmed state.

> **Session state lives in `handoff.md` on disk — not in any terminal process.** After `claudart setup`, close that terminal. The session is unaffected. Continue from the integrated terminal inside your editor.

### Good and bad usage

| Scenario | ✓ Do this | ✗ Not this | Why |
|---|---|---|---|
| Moving from `/suggest` to `/debug` | Run `/save` first | Jump straight to `/debug` | Preflight blocks — status must be `ready-for-debug` and a checkpoint must exist |
| `/debug` hits a wall | Let Claude write `needs-suggest`, then run `/suggest` | Force debug to continue | `needs-suggest` is the explicit reverse-direction signal — it exists for this case |
| Branch switch mid-session | `claudart status` to check, proceed knowingly | Ignore the branch warning | Debug runs against the wrong session context |
| Session still open from yesterday | `claudart status` then continue or `claudart kill` | `claudart setup` over the top | Setup warns on active handoff and requires confirmation |
| Working on two projects | Each project has its own isolated workspace | Share one workspace | `~/.claudart/<project>/` — fully isolated per project |
| Sensitive class names in handoff | Enable sensitivity mode at `claudart link` | Manually redact | Abstraction is automatic and persistent — manual redaction drifts |

---

## Session state

The session has a typed status that both `/suggest` and `/debug` read and enforce. It is represented as the `HandoffStatus` enum in `session_state.dart`.

### Status transitions

| Status | Written by | Read / enforced by | What to do next |
|---|---|---|---|
| `suggest-investigating` | `claudart setup` | `/save` · `claudart status` · launcher | Run `/suggest` — root cause not yet confirmed |
| `ready-for-debug` | `/suggest` | preflight gate · `/save` · `claudart status` | Run `/save` to checkpoint, then `/debug` |
| `debug-in-progress` | `/debug` | preflight (allows resume) · `/save` | Continue or `/save` to checkpoint progress |
| `needs-suggest` | `/debug` on blocker | preflight (blocks new `/debug`) · `claudart status` | Run `/suggest` to resolve the blocker first |
| `unknown` | Parse fallback | `claudart status` · launcher | Run `claudart setup` — file is blank or corrupted |

### Why a typed enum

`HandoffStatus` is a Dart enum with an exhaustive `switch` in every command that reads the handoff. The Dart compiler rejects unhandled cases and catches typos at build time, not runtime. Adding a new status requires updating every switch or the build fails. The compiler is the cheapest enforcer of session state correctness — no tests needed to catch a misspelled string.

---

<details>
<summary><strong>Commands reference</strong></summary>

## Commands at a glance

| Command | What it does |
|---|---|
| `claudart` | Interactive launcher — lists projects, routes you in |
| `claudart init` | One-time workspace setup |
| `claudart init --project name` | Register a new project |
| `claudart link` | Wire workspace into current project via symlinks |
| `claudart setup` | Start a session — writes handoff.md |
| `claudart save` | Checkpoint session — snapshot handoff, deposit confirmed root cause to skills.md |
| `claudart kill` | Abandon session — archive handoff, remove symlink (no skills update) |
| `claudart preflight <op>` | Sync check before starting an operation (`debug` \| `save` \| `test`) |
| `claudart status` | Show current session state |
| `claudart teardown` | End session — update knowledge, archive, suggest commit |
| `claudart flow` | [experimental] Freeform prompt → classify → plan → handoff |
| `claudart archives` | List session archives; resume or view past session snapshots |
| `claudart unlink` | Remove workspace symlinks from project |
| `claudart scan` | Re-scan project for sensitive tokens |
| `claudart map` | Generate a human-readable token map |
| `claudart report` | Show diagnostic summary |
| `claudart report --file-issue` | File issues to GitHub automatically |

</details>

---

<details>
<summary><strong>Workspace configuration — workspace.json + typed enums</strong></summary>

Each workspace has a `workspace.json` that defines the governing session model. Agent 1 (`/setup`) reads it and compiles `scaffold.md`. Session agents (Agent 2) read `scaffold.md` — never `workspace.json` directly.

```json
{
  "owner": {
    "name": "Aksana Buster",
    "email": "ab@liitx.com",
    "handle": "liitx"
  },
  "project": {
    "name": "zedup",
    "stack": ["dart"],
    "repo": "https://github.com/liitx/zedup",
    "role": "maintainer"
  },
  "session": {
    "agents": ["setup", "suggest", "debug", "save", "teardown"],
    "knowledge": ["dart_flutter", "testing", "enum-vs-variable", "git-authorship"],
    "proofNotation": "dart-grounded",
    "sensitivityMode": false
  }
}
```

All variant fields are parsed into typed enums by `lib/workspace/workspace_config.dart`. No command compares raw strings from this file.

### Enum contracts

#### `StackType`
`dart` · `flutter` · `bloc` · `riverpod` · `typescript` · `react` · `swift` · `kotlin`

Determines which generic knowledge files are relevant. `/setup` loads only files the stack declares.

#### `AgentType`
`setup` · `suggest` · `debug` · `save` · `teardown`

Declares which slash commands are in scope for this workspace. Unknown values are dropped at parse time.

Each variant carries two members that drive `claudart link` automatically:

| Member | Type | Contract |
|---|---|---|
| `fileName` | `String` | `'$name.md'` — slash command filename installed into `.claude/commands/` |
| `commandTemplate(workspace)` | `String` | Exhaustive `switch` — dispatches to the correct template function |

`link.dart` iterates `AgentType.values` in a single loop; adding a new agent variant requires only a new enum case and template function — the install loop never changes. The exhaustive `switch` in `commandTemplate` makes a missing template arm a compile error.

#### `WorkspaceRole`
`maintainer` · `contributor`

**Invariant:** `(role == maintainer) ↔ (WorkspaceRole.canUpdateReadme == true)` — enforced at teardown. `contributor` workspaces skip README updates entirely; the README belongs to the repo owner.

#### `ProofNotation`
`dart-grounded` · `ts-grounded` · `generic`

`dart-grounded`: use `∀`, `∃`, `∧`, `∨`, `↔` with Dart expressions. Never use `iff` — express bidirectional logic as `↔` with Dart on both sides. Every proof cites the Dart mechanism enforcing it (`const` constructor, null-safety, exhaustive `switch`, `assert()`).

### scaffold.md

`/setup` compiles all of the above into a single `scaffold.md` per workspace — owner identity, stack, proof notation, and summarised generic knowledge. Session agents load this once and do not re-read the originals. This keeps every session's context window narrow.

Re-run `/setup` whenever `workspace.json` changes.

</details>

---

<details>
<summary><strong>Skills &amp; the continuous improvement loop</strong></summary>

Every session makes the next one smarter. `skills.md` is the cross-session knowledge base — it accumulates from every session and is queried at the start of each new one.

```
Session ends
    ↓
claudart teardown prompts for learnings
    ↓                         ↓
Root Cause Patterns       Hot Paths · Anti-patterns
Branch Notes · Session Index
    ↓
Next session: /suggest reads relevant sections via cosine similarity
```

### skills.md structure

| Section | Written by | Read by | Content |
|---|---|---|---|
| `## Pending` | `claudart save` | `/suggest` | Confirmed root causes + hot file paths from in-progress sessions |
| `## Hot Paths` | `claudart teardown` | `/suggest` | Files confirmed key to past fixes |
| `## Root Cause Patterns` | `claudart teardown` | `/suggest` | What went wrong and how it was fixed, generically |
| `## Anti-patterns` | `claudart teardown` | `/suggest` | Files explored but not the root cause |
| `## Branch Notes` | `claudart teardown` | `/suggest` | Per-branch resolution log |
| `## Session Index` | `claudart teardown` | — | Flat log of all resolved sessions |

`claudart teardown` prompts you for learnings (category, hot files, cold files, pattern, fix pattern) and writes them directly to the relevant sections. It does not process or promote the `## Pending` section — that accumulates from `/save` as an in-session staging area.

`/suggest` does not read all of `skills.md`. It selects the top-3 most relevant sections using sparse TF-IDF cosine similarity against the current bug description. After 20 sessions, it surfaces 3 patterns, not 20.

</details>

---

<details>
<summary><strong>Privacy &amp; sensitivity protection</strong></summary>

When working on a proprietary codebase, class names, function signatures, and module structure may be confidential. claudart has an opt-in sensitivity mode.

### What gets abstracted

| Your code | What Claude sees |
|---|---|
| `VolumeBloc` | `Bloc:A` |
| `AudioState` | `BlocState:A` |
| `AudioRepository` | `Repository:A` |
| `fetchTrack(String id)` | `[Method:A]([Param:A])` |

### What is never abstracted

Flutter and Dart framework vocabulary — `Bloc`, `Cubit`, `Provider`, `BuildContext`, `StreamSubscription`, `StatelessWidget`, standard architectural pattern names — is never abstracted. Only project-specific identifiers are candidates. The safe list uses TF-IDF rarity scoring against a bundled Dart/Flutter corpus: common framework terms score low (safe), project-specific identifiers score high (abstract).

### When abstraction happens

```
claudart setup
  ↓  scans changed Dart files (if sensitivity mode on)
  ↓  builds / updates token_map.json
  ↓  abstracts handoff.md content before writing to disk
────────────────────────────────── ← Anthropic API boundary
  ↓  Claude Code reads abstracted handoff.md
```

**KT writes are also protected.** When `/save` deposits the confirmed root cause to `skills.md → Pending`, it passes through the same abstractor first. Sensitive identifiers never appear in `skills.md` in plaintext.

**To enable:**
```
claudart link
→ Enable sensitivity mode? y
```

**Local reference — `claudart map`** generates a human-readable cross-reference so you can always map abstract tokens back to real names:

```markdown
## Blocs
| Token  | Event       | State       | Dependencies |
|--------|-------------|-------------|--------------|
| Bloc:A | BlocEvent:A | BlocState:A | Repository:A |
```

The token map is append-only. Once `VolumeBloc → Bloc:A`, that mapping is permanent. Renamed class: `renamedTo` field added. Deleted class: `deprecated: true`. Tokens are never reused for different classes. Anthropic's understanding of `Bloc:A` accumulates correctly across every session.

</details>

---

<details>
<summary><strong>Git, PR &amp; test curation</strong></summary>

### Workspace isolation

Each user's workspace (`~/.claudart/<project>/`) is fully isolated and lives outside all git repositories — git never touches workspace files. Multiple projects on the same machine each have their own workspace. Workspace files are never committed.

### Contributing to claudart

Users interact with claudart's output (their workspace), not its source. Changing claudart itself requires a PR:

```
fork liitx/claudart
  → feature branch (e.g. feature/my-change)
  → open PR
  → CI: dart test --test-randomize-ordering-seed=random
  → review + merge
```

The gate is controlled. Workspace changes never become PRs — only source changes do.

### Feedback loop

```
User hits a bug
  → claudart report --file-issue
  → files GitHub issue on liitx/claudart
  → reviewed and triaged by maintainer
```

### Test enforcement

Feature tests live in `test/commands/`, `test/session/`, `test/sensitivity/`. Each module has a `test_<module>.md` file documenting scope, owned behaviors, and coverage gaps.

`readme_sync_test.dart` enforces documentation accuracy automatically:

| What it checks | How |
|---|---|
| Every `HandoffStatus` value has a Glossary entry | Reads enum values from source, checks README |
| Every "Used by" file exists on disk | Parses Glossary, checks `lib/` |
| Every string value in Glossary matches `.value` getter | Cross-checks README strings vs enum source |
| Every file in Architecture section exists in `lib/` or `bin/` | Extracts basenames, checks disk |
| Every command in Commands table is dispatched in `bin/claudart.dart` | Parses README table, checks dispatch switch |

Run `/readme` in Claude Code after any feature change to sync documentation automatically.

</details>

---

<details>
<summary><strong>Glossary</strong></summary>

> The Glossary documents the precise vocabulary used in code, docs, and tests. The [readme sync test](test/readme_sync_test.dart) verifies 1:1 correspondence: every `HandoffStatus` enum value must have an entry, every "Used by" file must exist on disk, every string value must match the `.value` getter. Run `/readme` to sync after any feature change.

---

### `HandoffStatus`

The typed representation of a session's current state. Owned by `lib/session/session_state.dart`. Replaces all magic string comparisons — every command that reads the handoff switches exhaustively on this enum. The Dart compiler enforces that all values are handled and catches typos at build time, not at runtime.

**Values:** `suggestInvestigating` · `readyForDebug` · `debugInProgress` · `needsSuggest` · `unknown`

Commands that read handoff status: `save.dart`, `status.dart`, `launch.dart`, `sync_check.dart`
Commands that never read handoff status: `setup.dart`, `kill.dart`, `link.dart`, `init.dart`, `unlink.dart`, `scan.dart`, `map_cmd.dart`, `report.dart`

---

#### `HandoffStatus.suggestInvestigating`

> `/suggest` is actively exploring. Root cause not yet confirmed.

**String value:** `suggest-investigating`
**Used by:** `save.dart` · `status.dart` · `launch.dart`
**Not used by:** `sync_check.dart` (no preflight check for this value), `setup.dart`, `kill.dart`

**Example — handoff.md:**
```
## Status
suggest-investigating
```

**Rule:** `/save` skips the `skills.md` Pending entry when status is `suggestInvestigating` — root cause is not yet confirmed so there is nothing to checkpoint. The archive snapshot is still written.
**Cannot change:** The string `suggest-investigating` is written verbatim to `handoff.md` and every archive snapshot. Renaming it silently breaks all existing sessions.

---

#### `HandoffStatus.readyForDebug`

> `/suggest` has identified a root cause. Run `/save` to lock it, then `/debug` to implement the fix.

**String value:** `ready-for-debug`
**Used by:** `sync_check.dart` · `save.dart` · `status.dart` · `launch.dart`
**Not used by:** `setup.dart`, `kill.dart`, `link.dart`, `init.dart`

**Example — handoff.md:**
```
## Status
ready-for-debug
```

**Rule:** `sync_check.dart` (via `preflight_cmd.dart`) blocks `/debug` unless status is `readyForDebug` or `debugInProgress`. `/save` must be run between `/suggest` and `/debug` — it is the required handshake that locks the confirmed root cause into `skills.md → ## Pending`.
**Cannot change:** The string `ready-for-debug` is the gate value in `checkHandoffStatus`. Renaming it without migrating all existing `handoff.md` files silently bypasses the debug preflight.

---

#### `HandoffStatus.debugInProgress`

> `/debug` has started implementing the fix. The session is mid-repair.

**String value:** `debug-in-progress`
**Used by:** `sync_check.dart` · `save.dart` · `status.dart` · `launch.dart`
**Not used by:** `setup.dart`, `kill.dart`, `link.dart`, `init.dart`

**Example — handoff.md:**
```
## Status
debug-in-progress
```

**Rule:** `sync_check.dart` allows `/debug` to resume when status is `debugInProgress` — it does not re-block if debug was already running. `/save` can be run mid-debug to checkpoint incremental progress.
**Cannot change:** The string `debug-in-progress` is written by the `/debug` slash command template. Renaming it without updating the template leaves sessions stuck at `unknown`.

---

#### `HandoffStatus.needsSuggest`

> `/debug` hit a blocker it cannot resolve. Broader exploration is needed before repair can continue.

**String value:** `needs-suggest`
**Used by:** `sync_check.dart` · `save.dart` · `status.dart` · `launch.dart`
**Not used by:** `setup.dart`, `kill.dart`, `link.dart`, `init.dart`

**Example — handoff.md:**
```
## Status
needs-suggest
```

**Rule:** `checkHandoffStatus` surfaces an error when `/debug` is attempted with `needsSuggest` status, directing the user back to `/suggest`. It is the only status where the workflow explicitly reverses direction.
**Cannot change:** The string `needs-suggest` is written by the `/debug` slash command template on blocker detection. Renaming it without updating the template silently drops the reverse-direction signal.

---

#### `HandoffStatus.unknown`

> Status field is missing, empty, or contains an unrecognised value. Treated as a fresh or corrupted session.

**String value:** _(none — this is the parse fallback for any unrecognised string)_
**Used by:** `session_state.dart` · `status.dart` · `save.dart` · `launch.dart`
**Not used by:** `sync_check.dart` (unknown is not a condition any preflight check distinguishes)

**Example — what triggers it:**
```
## Status
          ← blank, or any string not matching the four canonical values
```

**Rule:** `HandoffStatus.fromString` returns `unknown` for any input that does not match the four canonical strings — it never throws. Commands treat `unknown` as "needs setup": `status.dart` suggests running `claudart setup`, `launch.dart` shows the start-new-session menu.
**Cannot change:** `unknown` is a Dart-side sentinel, not a value the workflow writes intentionally. If it appears in a handoff, the file was manually edited or corrupted — it is a signal to run `claudart setup`, not a state to route on.

---

#### `HandoffStatus.noHandoff`

> No active claudart session — `CLAUDART_PROJECT` is unset or `handoff.md` is absent. Used by consumer tools (zedup) to represent the "no session running" state without conflating it with a corrupt or unknown session.

**String value:** `no-handoff`
**Used by:** `session_state.dart`
**Not used by:** any claudart command (never written to disk; claudart commands require a workspace)

**Rule:** `noHandoff` is emitted by zedup's `ContextRouter` when no project directory is configured. It is never written to `handoff.md` — it only exists as an in-memory sentinel so consumers can distinguish "no session" from "corrupt session" (`unknown`).
**Cannot change:** zedup and any other claudart consumer depends on this value being distinguishable from `unknown`. Merging them would break routing logic that treats "no session" as a normal initial state rather than an error.

---

### `AgentFlow`

The typed registry of all agent pipeline variants. Every flow has a `preferredModel`, a step list (or empty for dynamically-constructed flows), and a `hasCommandFile` flag indicating whether a slash-command `.md` file is installed by `claudart link`. Adding a new variant forces all exhaustive switches to update — the compiler enforces coverage.

**Values:** `suggest` · `debug` · `setup` · `save` · `teardown` · `flow` · `research` · `free` · `cli`
**Owned by:** `lib/pipeline/agent_flow.dart`

---

#### `AgentFlow.suggest`

> Deep exploration and knowledge-transfer session. `/suggest` runs the suggest pipeline: haiku reads scope files, sonnet reasons over findings and writes the handoff KT.

**Preferred model:** `opus` (deepest reasoning for root-cause exploration); pipeline steps use their own step-level models
**Has command file:** `true` (installs `suggest.md`)
**Used by:** `suggest.dart` · `agent_flow.dart`

---

#### `AgentFlow.debug`

> Deterministic scoped implementation — minimal diff, no exploration. `/debug` executes the path defined in the handoff.

**Preferred model:** `sonnet`
**Has command file:** `true` (installs `debug.md`)
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.setup`

> Session setup — workspace init, handoff scaffold. Runs haiku-tier agents to produce a fresh handoff template.

**Preferred model:** `haiku`
**Has command file:** `true` (installs `setup.md`)
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.save`

> Checkpoint session — snapshot handoff, deposit confirmed facts to skills. Lightweight; haiku suffices.

**Preferred model:** `haiku`
**Has command file:** `true` (installs `save.md`)
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.teardown`

> Session teardown — close workspace, update project README. Haiku-tier; no exploration required.

**Preferred model:** `haiku`
**Has command file:** `true` (installs `teardown.md`)
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.flow`

> Agent-constructed session — user provides freeform prompt; agents classify, plan, get approval, and construct the handoff automatically. Experimental variant of suggest. Steps accessed dynamically via `FlowSteps.*` in `flow.dart`.

**Preferred model:** `sonnet`
**Has command file:** `true` (installs `flow.md`)
**Used by:** `flow.dart` · `agent_flow.dart`

---

#### `AgentFlow.research`

> Constrained single-doc lookup — fast, targeted reference answer. No slash-command file; used internally by zedup's `@-reference` routing.

**Preferred model:** `haiku`
**Has command file:** `false`
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.free`

> Conversational — no context injection, balanced default. Used by zedup for free-form questions without any session context.

**Preferred model:** `sonnet`
**Has command file:** `false`
**Used by:** `agent_flow.dart`

---

#### `AgentFlow.cli`

> CLI shell-out — no API call, no pipeline steps. Used by zedup for slash commands that delegate to claudart CLI directly (e.g. `/save`, `/status`, `/teardown`). `preferredModel` is null.

**Preferred model:** none (`null`)
**Has command file:** `false`
**Used by:** `agent_flow.dart` · `agent_flow_ext.dart` (zedup)

---

### Sensitivity abstraction choices

When sensitivity mode is on, claudart applies token abstraction at two points in the user flow:

1. **`claudart setup`** — scans changed Dart files, updates `token_map.json`, abstracts `handoff.md` content before writing to disk
2. **`/save`** — passes confirmed root cause content through the abstractor before depositing to `skills.md → Pending`

The abstraction is deterministic and relational: tokens preserve semantic relationships (`Extension:A on Bloc:A`), not just names. The token map is append-only — tokens are never reassigned or reused.

**Framework vocabulary is on the safe list.** Dart SDK, Flutter, BLoC, Riverpod, and standard architectural pattern names (`Bloc`, `Cubit`, `Repository`, `Provider`, `BuildContext`, etc.) are never abstracted regardless of rarity score. Only identifiers not in the framework corpus are candidates. The corpus will be expanded from ~100 terms to full Dart/Flutter framework coverage in a future update.

</details>

---

<details>
<summary><strong>Architecture</strong></summary>

```mermaid
graph LR
    bin["bin/claudart.dart\ncommand dispatch"]

    subgraph commands["lib/commands/"]
        direction TB
        A["setup · save · kill · teardown\nlink · launch · preflight · status\ninit · unlink · scan · report · map"]
        B["setup_template · suggest_template · debug_template\nsave_template · teardown_template"]
    end

    subgraph session["lib/session/"]
        C["session_state\nHandoffStatus enum"]
        D["session_ops\ntransactional close"]
        E["sync_check\npreflight pure functions"]
        F["workspace_guard\nlock file"]
    end

    subgraph sensitivity["lib/sensitivity/"]
        G["detector\nTF-IDF + regex"]
        H["token_map\nrelational · append-only"]
        I["abstractor\nreplace / restore"]
    end

    subgraph workspace["lib/workspace/"]
        W["workspace_config\nStackType · AgentType\nWorkspaceRole · ProofNotation"]
    end

    subgraph core["lib/ — shared infrastructure"]
        J["file_io\ninjectable I/O interface"]
        K["registry\nproject index"]
        L["paths · md_io · git_utils\nlogging · similarity/cosine"]
    end

    bin --> commands
    commands --> session
    commands --> sensitivity
    commands --> workspace
    commands --> core
    session --> core
    sensitivity --> core
    workspace --> core
    D --> F
    E --> C
    I --> G
    I --> H
```

```
bin/claudart.dart           ← entry point + command dispatch

lib/
  commands/
    init.dart               ← workspace + project initialization
    launch.dart             ← interactive launcher menu (registry-driven, phase-separated)
    link.dart               ← registry entry creation, symlinks, .gitignore, sensitivity mode
    unlink.dart             ← safe symlink removal
    setup.dart              ← session start, scan trigger, abstraction, logging
    save.dart               ← session checkpoint: snapshot handoff, deposit to skills.md Pending
    kill.dart               ← session abandon: archive + reset + unlink (no skills update)
    preflight_cmd.dart      ← preflight sync check CLI wrapper
    status.dart             ← display current handoff state
    teardown.dart           ← end session, update knowledge, archive
    scan.dart               ← on-demand project rescan
    report.dart             ← diagnostic bundle + GitHub issue filing
    map_cmd.dart            ← generate token_map.md
    suggest_template.dart   ← /suggest slash command definition (written to workspace)
    debug_template.dart     ← /debug slash command definition
    save_template.dart      ← /save slash command definition
    teardown_template.dart  ← /teardown slash command definition

  session/
    session_state.dart      ← immutable parsed view of handoff.md; owns HandoffStatus enum
    session_ops.dart        ← transactional session close with rollback
    workspace_guard.dart    ← lock file mechanism for interrupted state detection
    sync_check.dart         ← preflight pure functions: status, skills, branch, coverage gaps

  sensitivity/
    detector.dart           ← TF-IDF + regex sensitive token detection
    token_map.dart          ← persistent relational token map (load/save/assign)
    abstractor.dart         ← replace/restore sensitive tokens in text

  scanner/
    scanner.dart            ← Dart static analysis, entity extraction
    scan_threshold_exception.dart

  similarity/
    cosine.dart             ← sparse TF-IDF cosine similarity

  logging/
    logger.dart             ← interactions.jsonl, errors.jsonl, performance.md

  assets/
    corpus.dart             ← bundled IDF weights for safe Dart/Flutter terms

  workspace/
    workspace_config.dart   ← WorkspaceConfig parser; StackType, AgentType, WorkspaceRole, ProofNotation enums
  config.dart               ← legacy per-workspace config (config.json)
  ignore_rules.dart         ← .claudartignore pattern matching
  file_io.dart              ← abstract FileIO + RealFileIO (testability)
  git_utils.dart            ← detectGitContext(): root + branch in one git call
  process_runner.dart       ← abstract ProcessRunner + RealProcessRunner
  md_io.dart                ← markdown section read/write utilities
  handoff_template.dart     ← handoff.md template generator
  knowledge_templates.dart  ← starter knowledge content generators
  pubspec_utils.dart        ← SDK constraint extraction from pubspec.yaml
  teardown_utils.dart       ← pure utilities: extractBranch, extractSection, archiveName, etc.
  paths.dart                ← workspace path resolution + per-project path helpers
  registry.dart             ← immutable project registry (load/save/add/remove/touchSession)
```

**Key design patterns:**

- All file I/O goes through the `FileIO` interface — production uses `RealFileIO`, tests use `MemoryFileIO`
- All git calls go through `detectGitContext()` — one subprocess, root + branch together, no duplication
- Pure functions separated from side effects — `sync_check.dart`, `teardown_utils.dart`, `knowledge_templates.dart`, `md_io.dart` have no I/O side effects and are trivially testable
- Injectable parameters (`exitFn`, `confirmFn`, `pickFn`, `projectRootOverride`) on every command — prevents `exit()` from terminating the test process
- Transactional session close in `session_ops.dart` — archive → reset → unlink with full rollback on any step failure
- `HandoffStatus` enum — exhaustive switch enforcement catches unhandled statuses and typos at build time
- `WorkspaceConfig` — `workspace.json` parsed into typed enums (`StackType`, `AgentType`, `WorkspaceRole`, `ProofNotation`); no command compares raw strings from the config file

**346 tests. Zero warnings on `dart pub publish --dry-run`.**

</details>

---

<details>
<summary><strong>Workspace structure — everything on disk</strong></summary>

```
~/.claudart/
  registry.json               ← index of all registered projects (name, root, workspace path)

  my-app/                     ← per-project workspace (created by claudart link)
    workspace.json            ← governing session model: owner, stack, role, agents, knowledge scope
    scaffold.md               ← compiled by /setup from workspace.json — inherited by all session agents
    handoff.md                ← current session state (reset each teardown)
    skills.md                 ← cross-session index: pending, hot paths, root causes, anti-patterns
    archive/                  ← every past session + checkpoints, timestamped
    knowledge/
      generic/
        dart_flutter.md       ← generic Dart/Flutter best practices (version-tagged)
        bloc.md               ← BLoC patterns accumulated from real sessions
        riverpod.md           ← Riverpod patterns
        testing.md            ← testing patterns
        enum-vs-variable.md   ← feature design decision + proof notation standard
        git-authorship.md     ← commit attribution — tool is invisible, owner is the author
        workspace-config.md   ← workspace.json schema and enum definitions
        agent-architecture.md ← two-agent model: Agent 1 (setup) vs Agent 2 (session)
      projects/
        my-app.md             ← project-specific context and accumulated patterns
    token_map.json            ← [sensitivity mode] persistent abstract token map
    config.json               ← legacy per-workspace config (sensitivity mode, scan scope)
    logs/
      interactions.jsonl      ← per-command structured log (capped at 500 entries)
      errors.jsonl            ← error log with deduplication by fingerprint
      performance.md          ← scan timing and token counts
    .claude/
      commands/
        setup.md              ← /setup slash command — Agent 1, compiles scaffold.md
        suggest.md            ← /suggest slash command — Agent 2
        debug.md              ← /debug slash command — Agent 2
        save.md               ← /save slash command — Agent 2
        teardown.md           ← /teardown slash command — Agent 2, updates README if maintainer
```

The workspace is never inside a project. `claudart link` creates a `.claude` symlink from your project root to the workspace's `.claude/commands/` directory, making slash commands available in your editor.

</details>

---

<details>
<summary><strong>claudart link — registry-based project management</strong></summary>

`claudart link` does more than create symlinks. It:

1. Registers the project in `~/.claudart/registry.json` with name, project root, and workspace path
2. Creates an isolated workspace at `~/.claudart/<project-name>/`
3. Wires `.claude` symlink from project root to workspace commands directory — **skipped gracefully if `.claude/` already exists as a real directory** (e.g. when linking claudart to itself)
4. Writes `suggest.md`, `debug.md`, and `save.md` slash command templates to the workspace — always, regardless of symlink state
5. Auto-adds `.claude` to `.gitignore` when a symlink is created (skipped when `.claude/` is a real tracked directory)
6. Prompts for sensitivity mode — stored per-project in the registry

Re-linking an existing project updates the symlink and sensitivity mode while preserving the original `createdAt` timestamp and all existing workspace content.

</details>

---

<details>
<summary><strong>Preflight sync checks</strong></summary>

Before any operation that depends on the handoff, claudart runs a preflight check:

```
claudart preflight debug   ← run before /debug
claudart preflight save    ← run before /save
claudart preflight test    ← run before test suite (checks coverage maps too)
```

**1. Handoff status check**
For `debug`: handoff must be `ready-for-debug` or `debug-in-progress`. Any other status is an error.

**2. Skills sync check**
If a root cause is confirmed in the handoff, a matching entry must exist in `skills.md → ## Pending`. Missing entry means `/save` was skipped. Warning — does not block, but signals a missed checkpoint.

**3. Branch sync check**
Current git branch vs branch recorded in handoff header. Mismatch warns that you may be operating on the wrong session context.

**4. Coverage gap check** (test operation only)
Scans all `test_*.md` module files for coverage table rows marked `—`. Each declared gap is surfaced before the test run.

Preflight exits 0 for clean and warnings (workflow continues). Exits 1 for errors (workflow blocked).

</details>

---

<details>
<summary><strong>Sensitivity mode — token map internals</strong></summary>

**Detection: TF-IDF + regex**

Two layers decide what's sensitive:

1. **Regex heuristics** — `PascalCase` (class names), `camelCase` compound words (method names), `snake_case.dart` filenames
2. **TF-IDF rarity scoring** — project-specific identifiers don't appear in the bundled Dart/Flutter corpus, so they score high (abstract). Framework terms score low (safe).

**The token map is relational**

Tokens preserve semantic relationships:

```json
{
  "Bloc:A": { "r": "VolumeBloc", "e": "BlocEvent:A", "s": "BlocState:A", "deps": ["Repository:A"] },
  "BlocState:A": { "r": "AudioState", "b": "Bloc:A" },
  "Extension:A": { "r": "VolumeBlocX", "on": "Bloc:A" }
}
```

Claude sees `Extension:A on Bloc:A` — it can reason about the architecture without knowing the domain.

**Append-only, never reassigned.** Once `VolumeBloc → Bloc:A`, permanent. Renamed class: `renamedTo` field. Deleted: `deprecated: true`. Never reused.

**The API boundary:**

```
Raw Dart identifiers (your machine only)
  ↓  static analysis + token map
  ↓  abstracted content
─────────────────────────── ← Anthropic API boundary
  ↓  Claude Code reads abstracted handoff.md
```

</details>

---

<details>
<summary><strong>Static analysis scanner</strong></summary>

Regex-based pattern matching — no full AST parser, kept light for performance.

| Pattern | Entity type | Token prefix |
|---|---|---|
| `class X extends Bloc<E, S>` | BLoC | `Bloc:` |
| `class X extends Cubit<S>` | Cubit | `Cubit:` |
| `class XState` / `sealed class XState` | BLoC state | `BlocState:` |
| `class XEvent` / `sealed class XEvent` | BLoC event | `BlocEvent:` |
| `class XRepository` | Repository | `Repository:` |
| `class X extends StatelessWidget` | Widget | `Widget:` |
| `extension X on Y` | Extension | `Extension:` |
| `typedef X = ...` | Callback/typedef | `Callback:` |
| `final xProvider = Provider(...)` | Riverpod provider | `Provider:` |
| `enum X { }` | Enum | `Enum:` |
| `mixin X` | Mixin | `Mixin:` |
| `class X` (unmatched) | Generic class | `Class:` |

**Threshold protection** — default 300 files. Exceeded: claudart warns, suggests narrowing to `lib/` or adding `.claudartignore`.

**`.claudartignore`** — place at project root. Default patterns: `**/*.g.dart`, `**/*.freezed.dart`, `**/*.mocks.dart`, `build/`, `.dart_tool/`.

**Incremental rescans** — only modified files are reprocessed. Full rescan: `claudart scan --full`.

</details>

---

<details>
<summary><strong>Logging &amp; diagnostics</strong></summary>

| File | Cap | Content |
|---|---|---|
| `logs/interactions.jsonl` | 500 entries | One JSON line per command run |
| `logs/errors.jsonl` | 200 entries | Errors with deduplication by fingerprint |
| `logs/performance.md` | 50 entries | Scan timing table |

Rotation is silent — oldest entries dropped at cap. `logs/summary.json` preserves aggregate counts.

**Error deduplication** — fingerprint: `"$command.$errorType.$reason"`. Same error increments `count` instead of creating a new entry.

**Sensitivity in logs** — token map applied to stack traces before writing. Real identifiers never appear in log files.

**`claudart report --file-issue`** — reads `errors.jsonl`, checks fingerprints against existing GitHub issues on `liitx/claudart`, files a new issue or comments on the existing one with updated frequency. Uses system `gh` CLI.

</details>

---

<details>
<summary><strong>Cosine similarity — how relevant skills are selected</strong></summary>

`skills.md` is not dumped into context wholesale. claudart selects the top-K most relevant chunks using sparse TF-IDF cosine similarity:

1. Tokenize the session's bug description into a query vector (TF-IDF weighted, bundled corpus)
2. Tokenize each section of `skills.md` into chunk vectors (same weighting)
3. Compute sparse dot product between query and each chunk
4. Return the top-3 chunks by cosine score

Sparse vectors only — 20–50 non-zero dimensions per chunk instead of 800. After 20 sessions, `/suggest` reads 3 patterns, not 20.

</details>

---

## Token efficiency

Unstructured Claude Code sessions are expensive. Every time you start fresh, the model re-reads dozens of files to rebuild context it already had. claudart eliminates that.

| Approach | Files read per session | Context reused |
|---|---|---|
| Unstructured (no handoff) | 30–60+ speculative reads | None |
| claudart structured session | ~5–15 targeted reads | Bug, root cause, scope, past patterns |

The first self-hosted claudart session (see [`experiments/`](experiments/)) resolved a real bug with **~15 total file reads** across `/suggest` + `/debug` combined.

---

## What's coming

claudart is actively developed and self-hosted — bugs and improvements are found by running the tool on itself. The [`experiments/`](experiments/) directory logs each self-hosted session.

Tracked on [GitHub Issues](https://github.com/liitx/claudart/issues). Current priorities:

**CLI experience**
- Arrow-key interactive menus across all commands (no more numbered picks)
- Spinners and progress indicators during operations
- Per-operation and total session timing in output
- Teardown confirmation table — review all extracted values before committing to skills.md

**Workflow**
- Framework-agnostic setup questions (remove Flutter/BLoC-specific wording)
- `claudart setup` false-positive "No project linked" fix when `.claude/` is a real directory
- `setup.dart` and `teardown.dart` full registry migration

**Public API**
- `lib/claudart.dart` barrel — public API surface with doc comments, orientating file for Claude Code agents and pub.dev

**Quality**
- GitHub Actions CI enforcing randomized test ordering on every PR
- Corpus expansion — full Dart/Flutter framework vocabulary as allow-list
- README auto-sync on every feature change via `/readme` skill + `readme_sync_test.dart`

---

## License

MIT
