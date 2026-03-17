# claudart

A Dart CLI that gives your Claude Code sessions **memory, structure, and privacy**.

> Not an Anthropic product. Built for Claude Code + Dart/Flutter projects.

---

## The short version

Claude Code has no memory between sessions. claudart gives it one.

| Step | Command | Run in | What happens |
|---|---|---|---|
| 1 | [`claudart setup`](#a-session-step-by-step) | terminal | Describe the bug. claudart writes a structured [`handoff.md`](#a-session-step-by-step) |
| 2 | [`/suggest`](#a-session-step-by-step) | Claude Code | Claude explores the codebase, confirms root cause, writes KT to the handoff |
| 3 | [`/save`](#handoffstatusreadyfordebug) | Claude Code | Locks confirmed state into [`skills.md`](#the-continuous-improvement-loop). Required before `/debug` |
| 4 | [`/debug`](#a-session-step-by-step) | Claude Code | Scoped fix only. Reads the handoff. Refuses to start without a confirmed root cause |
| 5 | [`claudart teardown`](#the-continuous-improvement-loop) | terminal | Promotes learnings to skills.md. Archives session. Resets for next time |

> **`claudart` commands** run in your terminal. **`/suggest`, `/save`, `/debug`** are slash commands — type them in the Claude Code chat panel inside your editor.

[`/save`](#handoffstatusreadyfordebug) is the required handshake — it is the lock that prevents [`/debug`](#a-session-step-by-step) from working from stale [session state](#handoffstatus).

No cloud sync. No API keys. Everything lives in a [local workspace](#the-workspace) on your machine.

---

## Table of contents

- [Quick start](#quick-start)
- [How it works — the simple version](#how-it-works--the-simple-version)
- [Token efficiency](#token-efficiency)
- [Commands at a glance](#commands-at-a-glance)
- [Glossary](#glossary)
- [Privacy & sensitivity protection](#privacy--sensitivity-protection)
- [The continuous improvement loop](#the-continuous-improvement-loop)
- [Detailed docs](#detailed-docs)
- [What's coming](#whats-coming)

---

## Quick start

```bash
# 1. Clone and compile
git clone https://github.com/liitx/claudart ~/dev/claudart
cd ~/dev/claudart
dart compile exe bin/claudart.dart -o ~/bin/claudart

# 2. Add ~/bin to PATH (if not already)
echo 'export PATH=$HOME/bin:$PATH' >> ~/.zshrc
source ~/.zshrc

# 3. Link a project
cd ~/dev/my-app
claudart link          # registers project, creates workspace, wires .claude symlink

# 4. Start a session
claudart setup
# → then type /suggest inside Claude Code
```

**Recompile after updates:**
```bash
dart compile exe ~/dev/claudart/bin/claudart.dart -o ~/bin/claudart
```

---

## How it works — the simple version

### The workspace

Each registered project gets its own **isolated workspace** — a folder managed by claudart at `~/.claudart/<project-name>/`. It holds everything Claude needs to be useful: past learnings, project patterns, session state.

```
~/.claudart/
  registry.json           ← index of all registered projects
  my-app/
    handoff.md            ← current bug being worked on
    skills.md             ← what worked (and didn't) in past sessions
    archive/              ← every past session + checkpoints
    knowledge/            ← what Claude reads before every session
    .claude/commands/     ← slash command definitions (suggest, debug, save, teardown)
```

Projects never contain workspace state. `claudart link` wires a `.claude` symlink from your project root into the workspace at session time.

### A session, step by step

```
── Terminal ──────────────────────────────────────────────────
1. claudart setup
   Describe the bug. claudart writes a structured handoff.md.

── Claude Code (chat panel) ──────────────────────────────────
2. /suggest
   Reads your knowledge base + handoff.
   Explores the codebase. Confirms root cause.
   Writes findings to handoff.md. Sets status → ready-for-debug.

3. /save  ← required handshake
   Checkpoints the handoff to archive/.
   Deposits the confirmed root cause to skills.md → Pending.
   Does NOT reset the session — work continues.

4. /debug
   Reads the checkpointed handoff. Runs preflight — refuses to start
   if status is wrong or skills.md is out of sync.
   Implements a scoped fix. Only touches what it said it would touch.

── Terminal ──────────────────────────────────────────────────
5. claudart teardown
   Confirm the fix. Describe what changed.
   claudart extracts learnings, adds them to skills.md.
   Archives the session. Resets handoff. Suggests a commit message.
```

Every session makes the next one smarter. `/save` makes sure no confirmed knowledge is lost between steps.

> **Session state lives in `handoff.md` on disk — not in any terminal process.** After running `claudart setup` in an external terminal, you can close it and continue from the integrated terminal inside your editor. The session is unaffected.

### The handoff status machine

The session has a status that both `/suggest` and `/debug` respect:

| Status | Meaning |
|---|---|
| `suggest-investigating` | `/suggest` is exploring |
| `ready-for-debug` | `/suggest` is confident — run `/save`, then `/debug` |
| `debug-in-progress` | `/debug` is implementing |
| `needs-suggest` | `/debug` hit a wall — hand back to `/suggest` |

These statuses are represented internally as the `HandoffStatus` enum in `session_state.dart`. Every command that reads the handoff uses exhaustive switch statements on this enum — the Dart compiler enforces that all statuses are handled and catches typos at compile time.

`/debug` refuses to start unless status is `ready-for-debug` or `debug-in-progress`. `/save` is required between the two — it is the lock that prevents debug from working from stale state.

### Branch awareness

Every command that reads the handoff checks whether your current git branch matches the branch the session was started on. If you switch branches mid-session, claudart warns you before you save or debug against the wrong context. It never blocks — you can always proceed — but the warning is explicit.

---

## Token efficiency

Unstructured Claude Code sessions are expensive. Every time you start fresh, the model re-reads dozens of files to rebuild context it already had. claudart eliminates that.

| Approach | Files read per session | Context reused |
|---|---|---|
| Unstructured (no handoff) | 30–60+ speculative reads | None |
| claudart structured session | ~5–15 targeted reads | Bug, root cause, scope, past patterns |

**How it works:**

- `handoff.md` gives Claude a precise entry point — bug description, confirmed root cause, files in scope. No re-discovery.
- `skills.md` is queried with sparse TF-IDF cosine similarity — only the top-3 most relevant past patterns are surfaced, not the full history.
- `/suggest` explores within declared scope only. It does not speculatively read the whole codebase.
- Sensitivity abstraction produces shorter tokens for abstracted identifiers — `Bloc:A` instead of `AudioPlayerBlocImplementation`.

The first self-hosted claudart session (see `experiments/`) resolved a real bug with **~15 total file reads** across `/suggest` + `/debug` combined.

---

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
| `claudart unlink` | Remove workspace symlinks from project |
| `claudart scan` | Re-scan project for sensitive tokens |
| `claudart map` | Generate a human-readable token map |
| `claudart report` | Show diagnostic summary |
| `claudart report --file-issue` | File issues to GitHub automatically |

---

## Glossary

> Indexed by the canonical types and values used in the codebase. Each entry maps a concept to where it is and is not used, a minimal example, the rule it enforces, and any immutability constraints — so the vocabulary in code, docs, and tests stays the same word.
>
> The [readme sync test](test/readme_sync_test.dart) verifies 1:1 correspondence: every `HandoffStatus` enum value must have an entry, every "Used by" file must exist on disk, every string value must match the `.value` getter. Run `/readme` to sync after any feature change.

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

## Privacy & sensitivity protection

When you're working on a proprietary codebase, you might not want class names, function signatures, or module structure going to Anthropic's servers verbatim.

**claudart has an opt-in sensitivity mode.**

When enabled during `claudart link`, it:

1. Scans your project's Dart files for sensitive identifiers (class names, BLoC types, repository names, typedefs, etc.)
2. Assigns them stable abstract tokens: `AudioBloc` → `Bloc:A`, `VehicleRepository` → `Repository:A`
3. Builds a **persistent local token map** that grows across sessions
4. Replaces sensitive identifiers in `handoff.md` *before* Claude reads it

Claude sees the full picture — BLoC types, relationships, dependency graphs — just never the real names.

**KT writes are also protected.** When `/save` deposits the confirmed root cause and hot file paths into `skills.md → ## Pending`, it passes that content through the same abstractor first. Sensitive identifiers never appear in `skills.md` in plaintext — the knowledge base stays private even as it grows.

```
Your code                    What Claude sees
─────────────────────        ────────────────────────────────────
AudioBloc                →   Bloc:A
AudioState               →   BlocState:A
AudioRepository          →   Repository:A
fetchTrack(String id)    →   [Method:A]([Param:A])
```

The token map lives locally. It never leaves your machine. Anthropic builds understanding of `Bloc:A` across sessions without ever learning it's called `AudioBloc`.

**To enable:**
```
claudart link
→ Enable sensitivity protection? y
→ Scan scope: lib/ only (recommended)
→ Scan trigger: On setup (when files changed)
→ Share anonymous diagnostic logs? y/n
```

**Your local reference key** — `claudart map` generates a human-readable table so you can always cross-reference abstract tokens back to real names:

```markdown
## Blocs
| Token      | Event        | State        | Dependencies |
|------------|--------------|--------------|--------------|
| Bloc:A     | BlocEvent:A  | BlocState:A  | Repository:A |

## Repositories
| Token        | Returns  | Async |
|--------------|----------|-------|
| Repository:A | Model:A  | yes   |
```

---

## The continuous improvement loop

```
Session ends
    ↓
claudart teardown extracts learnings
    ↓                    ↓
Generic patterns    Project patterns
(all projects)      (this project only)
    ↓
Next session: agents start with richer context automatically
```

`skills.md` accumulates:
- **Pending** — confirmed root causes from in-progress sessions (written by `/save`, promoted by `teardown`)
- **Hot paths** — files that keep showing up across sessions
- **Root cause patterns** — generic descriptions of what went wrong and how it was fixed
- **Anti-patterns** — files that looked relevant but weren't

Over time, `/suggest` stops re-exploring dead ends it already visited.

---

## Detailed docs

<details>
<summary><strong>Workspace structure — everything that lives on disk</strong></summary>

```
~/.claudart/
  registry.json               ← index of all registered projects (name, root, workspace path)

  my-app/                     ← per-project workspace (created by claudart link)
    handoff.md                ← current session state (reset each teardown)
    skills.md                 ← cross-session index: pending, hot paths, root causes, anti-patterns
    archive/                  ← every past session + checkpoints, timestamped
    knowledge/
      generic/
        dart_flutter.md       ← generic Dart/Flutter best practices (version-tagged)
        bloc.md               ← BLoC patterns accumulated from real sessions
        riverpod.md           ← Riverpod patterns
        testing.md            ← testing patterns
      projects/
        my-app.md             ← project-specific context and accumulated patterns
    token_map.json            ← [sensitivity mode] persistent abstract token map
    config.json               ← per-workspace config (sensitivity mode, scan scope, etc.)
    logs/
      interactions.jsonl      ← per-command structured log (capped at 500 entries)
      errors.jsonl            ← error log with deduplication by fingerprint
      performance.md          ← scan timing and token counts
    .claude/
      commands/
        suggest.md            ← /suggest slash command definition
        debug.md              ← /debug slash command definition
        save.md               ← /save slash command definition
        teardown.md           ← /teardown slash command definition
```

The workspace is never inside a project. `claudart link` creates a `.claude` symlink from your project root to the workspace's `.claude/commands/` directory, making slash commands available in your editor. The symlink is removed by `claudart kill` or `claudart teardown`.

</details>

<details>
<summary><strong>Preflight sync checks — how claudart keeps state consistent</strong></summary>

Before any operation that depends on the handoff, claudart runs a preflight check:

```
claudart preflight debug   ← run before /debug
claudart preflight save    ← run before /save
claudart preflight test    ← run before test suite (checks coverage maps too)
```

Three checks run on every preflight call:

**1. Handoff status check**
For `debug`: handoff must be `ready-for-debug` or `debug-in-progress`. Any other status is an error — `/suggest` hasn't finished.

**2. Skills sync check**
If a root cause is confirmed in the handoff, a matching entry must exist in `skills.md → ## Pending`. A missing entry means `/save` was skipped. This is a warning — it doesn't block the operation, but it means a checkpoint was missed.

**3. Branch sync check**
Current git branch is compared to the branch recorded in the handoff header. A mismatch warns you that you may be operating on the wrong session context.

**4. Coverage gap check** (test operation only)
Scans all `test_*.md` module files for coverage table rows marked `—`. Each declared gap is surfaced before the test run.

Preflight exits 0 for clean and warnings (workflow continues). Exits 1 for errors (workflow blocked).

</details>

<details>
<summary><strong>claudart link — registry-based project management</strong></summary>

`claudart link` does more than create symlinks. It:

1. Registers the project in `~/.claudart/registry.json` with name, project root, and workspace path
2. Creates an isolated workspace at `~/.claudart/<project-name>/`
3. Wires `.claude` symlink from project root to workspace commands directory — **skipped gracefully if `.claude/` already exists as a real directory** (e.g. when linking claudart to itself)
4. Writes `suggest.md`, `debug.md`, and `save.md` slash command templates to the workspace — always, regardless of symlink state
5. Reads `pubspec.yaml` to extract SDK/Flutter constraints for the generated `CLAUDE.md`
6. Auto-adds `.claude` to `.gitignore` when a symlink is created (skipped when `.claude/` is a real tracked directory)
7. Prompts for sensitivity mode — stored per-project in the registry

Re-linking an existing project updates the symlink and sensitivity mode while preserving the original `createdAt` timestamp and all existing workspace content.

</details>

<details>
<summary><strong>Sensitivity mode — how the token map works under the hood</strong></summary>

**Detection: TF-IDF + regex**

claudart uses two layers to decide what's sensitive:

1. **Regex heuristics** — `PascalCase` (class names), `camelCase` compound words (method names), `snake_case.dart` filenames. Anything matching these patterns is a candidate.
2. **TF-IDF rarity scoring** — claudart ships with a bundled frequency map of ~100 common Dart/Flutter terms (`String`, `BuildContext`, `BlocBuilder`, etc.). These score low (common = safe). Project-specific identifiers don't appear in the corpus, so they score high (rare = sensitive).

Anything flagged as sensitive and not in the safe list gets a stable abstract token.

**The token map is relational**

Tokens preserve semantic relationships, not just names:

```json
{
  "Bloc:A": { "r": "AudioBloc", "e": "BlocEvent:A", "s": "BlocState:A", "deps": ["Repository:A"] },
  "BlocState:A": { "r": "AudioState", "b": "Bloc:A" },
  "Extension:A": { "r": "AudioBlocX", "on": "Bloc:A" }
}
```

Claude sees `Extension:A on Bloc:A` and knows it's an extension on that specific BLoC. It can reason about the architecture without knowing the domain.

**Append-only, never reassigned**

Once `AudioBloc` → `Bloc:A`, that mapping is permanent. If the class is renamed, the old token gets a `renamedTo` field. If deleted, `deprecated: true`. The token is never reused for a different class. This means Anthropic's understanding of `Bloc:A` accumulates correctly across every session.

**The API boundary is enforced**

```
Raw Dart identifiers (your machine only)
  ↓  static analysis + token map
  ↓  abstracted content
─────────────────────────── ← Anthropic API boundary
  ↓  Claude Code reads abstracted handoff.md
```

If `isNotSensitive()` returns false after abstraction, claudart warns you before writing.

</details>

<details>
<summary><strong>Static analysis scanner — how entity detection works</strong></summary>

The scanner uses regex-based pattern matching (no full AST parser — kept light for performance).

**What gets detected:**

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

**Threshold protection**

Default threshold: 300 files. If exceeded:

```
⚠ Large scan detected
  └── 847 Dart files found in project root
  └── Estimated scan time: ~45s

This may be slow. Suggestions:
  1. Narrow scope to lib/ only    → claudart link --scope lib
  2. Add *.g.dart to .claudartignore
  3. Run: claudart scan --scope lib

? Switch to lib/ scope now and continue? (Y/n)
```

**`.claudartignore`**

Place at your project root. Default patterns applied if file is missing:

```
**/*.g.dart
**/*.freezed.dart
**/*.mocks.dart
build/
.dart_tool/
```

**Incremental rescans**

The scanner checks file mtimes against `lastScan` in `config.json`. Only modified files are reprocessed. Full rescan: `claudart scan --full`.

</details>

<details>
<summary><strong>Logging & diagnostics — what gets captured and why</strong></summary>

**Three log files, all capped:**

| File | Cap | Content |
|---|---|---|
| `logs/interactions.jsonl` | 500 entries | One JSON line per command run |
| `logs/errors.jsonl` | 200 entries | Errors with deduplication by fingerprint |
| `logs/performance.md` | 50 entries | Scan timing table |

Rotation is silent. When a file exceeds its cap, oldest entries are dropped. A `logs/summary.json` preserves aggregate counts so the signal is never fully lost.

**Error deduplication**

Every error gets a fingerprint: `"$command.$errorType.$reason"`. If the same error occurs again, it increments a `count` field on the existing entry instead of creating a new one. This means `errors.jsonl` stays small and meaningful even over many sessions.

**Sensitivity in logs**

If sensitivity mode is on, the token map is applied to stack traces before they're written to disk. Real identifiers never appear in log files.

**`claudart report --file-issue`**

Reads `errors.jsonl`, checks each entry's fingerprint against existing GitHub issues on `liitx/claudart`, and either:
- Files a new issue (labels: `claudart-generated`, error type) if none exists
- Comments on the existing issue with updated frequency if `count` crossed a threshold

Uses the system `gh` CLI. Falls back to PAT prompt if `gh` is not configured.

</details>

<details>
<summary><strong>Cosine similarity — how relevant context is selected</strong></summary>

When building the handoff, claudart doesn't dump all of `skills.md` into context. It selects the top-K most relevant chunks using sparse TF-IDF cosine similarity.

**How it works:**

1. Tokenize the session's bug description into a query vector (TF-IDF weighted, using the bundled corpus)
2. Tokenize each section of `skills.md` into chunk vectors (same weighting)
3. Compute sparse dot product between query and each chunk
4. Return the top-3 chunks by cosine score

Sparse vectors only — no full vocabulary materialization. For typical `skills.md` sections, vectors have 20–50 non-zero dimensions instead of 800. Fast and cheap.

This means that after 20 sessions, `/suggest` doesn't get overwhelmed with unrelated history — it gets the 3 most relevant past patterns.

</details>

<details>
<summary><strong>Architecture — how the code is organized</strong></summary>

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
    corpus.dart             ← bundled IDF weights for ~100 safe Dart/Flutter terms

  config.dart               ← WorkspaceConfig read/write (config.json)
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
- Pure functions are separated from side effects — `sync_check.dart`, `teardown_utils.dart`, `knowledge_templates.dart`, `md_io.dart` have no I/O side effects and are trivially testable
- Injectable parameters (`exitFn`, `confirmFn`, `pickFn`, `projectRootOverride`) on every command — prevents `exit()` from terminating the test process
- Transactional session close in `session_ops.dart` — archive → reset → unlink with full rollback on any step failure
- No new runtime dependencies — TF-IDF, cosine similarity, and static analysis are all implemented in pure Dart
- `HandoffStatus` enum in `session_state.dart` — replaces all magic string status comparisons; exhaustive switch enforcement means the compiler catches unhandled statuses and typos at build time, not at runtime

**346 tests. Zero warnings on `dart pub publish --dry-run`.**

</details>

---

## What's coming

claudart is actively developed and self-hosted — bugs and improvements are found by running the tool on itself. The [`experiments/`](experiments/) directory logs each self-hosted session.

Tracked on [GitHub Issues](https://github.com/liitx/claudart/issues). Current priorities:

**CLI experience**
- Arrow-key interactive menus across all commands (no more numbered picks)
- Spinners and progress indicators during operations
- Per-operation and total session timing displayed in output
- Teardown confirmation table — review all extracted values before committing to skills.md

**Workflow**
- Framework-agnostic setup questions (remove Flutter/BLoC-specific wording)
- `claudart setup` false-positive "No project linked" fix when `.claude/` is a real directory
- `setup.dart` and `teardown.dart` full registry migration

**Docs**
- Mermaid architecture diagram in README — interactive dependency graph (command → module → interface clusters), zoomable in GitHub and Cursor
- Glossary extended to cover `FileIO`, `Registry`, `SessionState`, and other core interfaces

**Quality**
- GitHub Actions CI enforcing randomized test ordering on every PR
- README auto-sync on every feature change via `/readme` skill + `readme_sync_test.dart`

---

## License

MIT
