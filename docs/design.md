# claudart — Formal Design

> Mathematical foundations, proofs, and diagrams for the claudart session workflow.
> Read alongside `experiments/2026-03-17-reasoning-design-session.md`.

---

## 1. Session State Machine

### Formal definition

Let **S** be the finite set of session states — the `HandoffStatus` enum
(`lib/session/session_state.dart`), 8 variants total:

```
S = { no-handoff, suggest-investigating, ready-for-suggest, ready-for-debug,
      debug-in-progress, debug-complete, needs-suggest, unknown }
```

`no-handoff` and `unknown` are sentinel values — never written to
handoff.md (see `HandoffStatus.value`'s doc comment). `no-handoff` is the
pre-session state (zedup-local, emitted when no handoff exists yet);
`unknown` is the parse-failure fallback for an unrecognized status string.
Neither participates in the transition table below; the automaton's real
work happens across the remaining 6 persisted states.

Let **C** be the finite set of commands:

```
C = { claudart setup, /suggest, /save, /debug, claudart rotate,
      claudart teardown, claudart kill }
```

The session is a **deterministic finite automaton** `(S, C, δ, s₀, F)` where:

- `s₀ = no-handoff` (initial state, before `claudart setup` writes a handoff)
- `F = { resolved }` (accepting / terminal state reached by teardown; not an
  `HandoffStatus` value itself — `debug-complete` transitions here via
  `/teardown`, at which point the handoff is archived and reset)
- `δ : S × C → S` is the transition function (total — every command has a defined outcome in every state)

**Transition function δ:**

| Current state | Command | Next state | Precondition |
|---|---|---|---|
| `no-handoff` | `claudart setup` | `suggest-investigating` | — |
| `suggest-investigating` | `/save` | `suggest-investigating` | root cause unconfirmed |
| `suggest-investigating` | `/save` | `ready-for-suggest` | root cause confirmed, further exploration expected |
| `suggest-investigating` | `/save` | `ready-for-debug` | root cause confirmed, ready to implement |
| `suggest-investigating` | `claudart rotate` | `suggest-investigating` (new session) | build gate passes |
| `ready-for-suggest` | `/save` | `ready-for-debug` | — |
| `ready-for-debug` | `/debug` | `debug-in-progress` | — |
| `ready-for-debug` | `claudart rotate` | `suggest-investigating` (new session) | build gate passes |
| `debug-in-progress` | `/save` | `debug-in-progress` | — |
| `debug-in-progress` | (blocked) | `needs-suggest` | debug hits a question suggest must resolve |
| `needs-suggest` | `/suggest` | `suggest-investigating` | — |
| `debug-in-progress` | fix verified | `debug-complete` | — |
| `debug-in-progress` | `claudart rotate` | `suggest-investigating` (new session) | build gate passes |
| `debug-complete` | `claudart teardown` | `resolved` (archived) | — |
| any | `claudart kill` | `∅` (handoff erased) | — |

**Key property:** `δ` is a real function in code: `HandoffStatus.after(HandoffEvent)` in
`lib/session/session_state.dart`, returning the next status or `null` when the table has no such move
(the move is rejected). It is *not* compiler-exhaustive — `after` switches over an `(event, status)` pair
with a `null` default — so completeness is proven by `test/session/handoff_transition_test.dart`, which checks every
`(status, event)` pair against an independent literal copy of this table, and checks that every persisted status is
reachable from `no-handoff` and has an exit.

**Consumer view.** A reset leaves the blank handoff on disk, whose Status line still reads
`suggest-investigating`. The status a consumer should show is `SessionState.effectiveStatus`: `no-handoff` when the
handoff has no active content, the parsed status otherwise. `test/conformance/lifecycle_test.dart` pins it step by step
across whole lifecycles, and `make consumer-check` replays the same scenarios against zedup's real reader.

**Events** (`lib/session/handoff_event.dart`) name outcomes, one per row above: `setup`, `saveUnconfirmed`,
`saveConfirmedExploring`, `saveConfirmedReady`, `debugStarted`, `debugBlocked`, `suggestResumed`, `fixApplied`, `rotated`,
`rotatedEmpty`, `tornDown`, `reminderSaved`, `killed`. `rotatedEmpty`, `tornDown`, `reminderSaved` and `killed` land in `no-handoff` (the handoff is reset or erased).

**Deliberate extensions to the table** (what the commands actually do today; each is a row in the code and its test):

| Current state | Event | Next state | Why |
|---|---|---|---|
| `ready-for-debug`, `debug-in-progress`, `needs-suggest` | `saveConfirmedReady` | `ready-for-debug` | `/suggest` re-run overwrites an existing handoff after the user confirms |
| `ready-for-debug`, `debug-in-progress` | `fixApplied` | `debug-complete` | `/debug` applies its plan and marks it complete in one step; claudart does not verify the fix, so "fix verified" is named for what happens |
| `suggest-investigating`, `ready-for-debug`, `debug-in-progress` | `rotatedEmpty` | `no-handoff` | `claudart rotate` with no pending issue archives the session and resets the handoff to blank |
| any persisted state | `reminderSaved` | `no-handoff` | `claudart teardown` on an unresolved session saves a reminder and resets the handoff |
| any persisted state | `killed` | `no-handoff` | `claudart kill` erases the handoff |

### State diagram

```mermaid
stateDiagram-v2
  [*] --> noHandoff
  noHandoff --> suggestInvestigating: /suggest
  suggestInvestigating --> readyForSuggest: explore
  readyForSuggest --> readyForDebug: /save
  readyForDebug --> debugInProgress: /debug
  debugInProgress --> needsSuggest: blocked
  needsSuggest --> suggestInvestigating
  debugInProgress --> debugComplete: fix verified
  debugComplete --> [*]: /teardown
```

Matches README.md's own diagram exactly — kept in sync deliberately;
`unknown` (parse-failure sentinel) and the `claudart kill`/`claudart
rotate` edges (available from any state, omitted here to keep the
diagram legible) are the two things this simplified view leaves out of
the full transition table above.

---

## 2. Coverage Model

### Definitions

```
T  =  set of all testable behaviors in the codebase
      (public functions + enum contracts + parse rules + branches)

C  =  set of behaviors with at least one assertion

Gap  =  T − C  (set difference)
```

**Theorem:** A session is complete if and only if `Gap = ∅`.

**Corollary:** Every operation that adds an element to `T` requires a test before the session closes.

### What adds to T

| Operation | Element added to T |
|---|---|
| New public function `f` | `{f}` |
| New enum variant `v` on enum `E` | `{(E, v, g) : g ∈ getters(E)}` |
| New getter `g` on enum `E` | `{(E, v, g) : v ∈ variants(E)}` |
| New regex or parse rule | one element per distinct input class |
| New branch in existing function | one element per new path |
| New record field | one element per constructor call site |

### Subset relationship

```
C ⊆ T     always (you cannot cover a behavior that doesn't exist)
C = T     session complete
C ⊂ T     gap exists — session not done
```

### Coverage diagram

```mermaid
graph TD
    subgraph T["T — all testable behaviors"]
        subgraph C["C — covered behaviors"]
            c1["extractBranch/happy path"]
            c2["HandoffStatus.fromString/all variants"]
            c3["appendToSection/blank → first entry"]
        end
        g1["⚠ extractPendingIssues/empty section"]
        g2["⚠ rotate/build gate fails"]
    end

    style T fill:#1a1a2e,stroke:#4a4a8a,color:#ccc
    style C fill:#0f3460,stroke:#4a9eff,color:#ccc
    style g1 fill:#3d0000,stroke:#ff4444,color:#ff8888
    style g2 fill:#3d0000,stroke:#ff4444,color:#ff8888
```

> When `g1` and `g2` exist, `Gap ≠ ∅` and the session is not complete.
> Both are now covered — see `test/session/teardown_utils_test.dart` and `test/commands/rotate_test.dart`.

---

## 3. Enum Test Matrix

### Definition

For an enum **E** with:
- Variants: `V = {v₁, v₂, ..., vₙ}`
- Getters: `G = {g₁, g₂, ..., gₘ}`

The **required test matrix** is the Cartesian product:

```
M(E)  =  V × G  =  { (vᵢ, gⱼ) : 1 ≤ i ≤ n, 1 ≤ j ≤ m }

|M(E)|  =  |V| × |G|    (required assertions)
```

**Proof that every cell is necessary:**

For any `(vᵢ, gⱼ) ∈ M(E)`, the assertion `expect(vᵢ.gⱼ, expectedValue)` is the only statement that can detect a regression in the mapping `gⱼ(vᵢ)`. No other test covers this cell because:
1. The getter `gⱼ` is a `switch` expression — each arm is independently reachable
2. A bug in arm `vᵢ` does not affect any other arm
3. Therefore each cell is an independent failure mode

### TeardownCategory matrix (concrete example)

`TeardownCategory` has 8 variants and 3 getters → `|M| = 8 × 3 = 24` required assertions.

| variant | `.value` | `.area` | `.label` |
|---|---|---|---|
| `apiIntegration` | `'api-integration'` | `'api'` | `'api-integration'` |
| `concurrency` | `'concurrency'` | `'async'` | `'concurrency'` |
| `configuration` | `'configuration'` | `'config'` | `'configuration'` |
| `dataParsing` | `'data-parsing'` | `'data'` | `'data-parsing'` |
| `ioFilesystem` | `'io-filesystem'` | `'io'` | `'io-filesystem'` |
| `stateManagement` | `'state-management'` | `'state'` | `'state-management'` |
| `general` | `'general'` | `'fix'` | `'general'` |
| `other` | `'other'` | `'fix'` | `'other (type manually)'` ← distinct |

All 24 cells are asserted in `test/session/teardown_utils_test.dart`.

**Matrix growth rule:**
- New variant added → new row → `m` new assertions required
- New getter added → new column → `n` new assertions required
- Both → `n + m + 1` new assertions required

---

## 4. Rotate — Formal Process Specification

### Pre/post conditions

```
Pre(rotate):
  handoff ≠ blankHandoff          -- active session exists
  user confirms                   -- explicit consent
  afterFixCommand ∈ config        -- build command is configured

Invariant (build gate):
  ∀ rotate call: afterFixCommand exits 0 before new handoff is written

Post(rotate) when pending ≠ ∅:
  archive ∈ archiveDir            -- old session preserved
  handoff.bug = pending[0]        -- first pending issue seeded
  handoff.pendingIssues = pending[1..]  -- queue advanced by one
  handoff.status = suggest-investigating  -- clean state for /suggest

Post(rotate) when pending = ∅:
  archive ∈ archiveDir            -- old session preserved
  handoff = blankHandoff          -- all issues resolved
```

### The build gate as an invariant proof

**Claim:** No session `n+1` can begin unless session `n`'s fix compiles.

**Proof:**
1. `rotate` archives the current handoff (write to archive/)
2. `rotate` calls `afterFixCommand` and awaits exit code
3. If `exitCode ≠ 0` → return `RotateResult.buildFailed`, handoff is NOT overwritten
4. If `exitCode = 0` → seed new handoff
5. Therefore: the only path to a new handoff is through a passing build ∎

**Why this matters:** The tool being self-hosted means the compiled binary at `~/bin/claudart` is what runs the next session. If the fix broke the build, the next session would run stale code. The gate makes this impossible.

### Rotate flow diagram

```mermaid
flowchart TD
    A(["/suggest\nFinds N bugs"]) --> B["Write Bug 1 to handoff\nWrite Bug 2..N to ## Pending Issues"]
    B --> C(["/save\nRoot cause confirmed"])
    C --> D(["/debug\nFix implemented"])
    D --> E{"claudart rotate"}

    E --> F["Archive current handoff"]
    F --> G{"Run afterFixCommand\nmake rebuild"}

    G -->|"exit ≠ 0\nbuild failed"| H["⛔ Abort\nHandoff untouched\nFix the build first"]
    G -->|"exit = 0\nbuild passed"| I{"pending issues?"}

    I -->|"yes"| J["Seed new handoff:\nbug ← pending[0]\npending ← pending[1..]"]
    I -->|"no"| K["Reset to blankHandoff\nAll issues resolved"]

    J --> L(["Run /suggest\nBug 2 pre-loaded\nskills.md has Bug 1 pattern"])
    K --> M(["Session complete"])

    style H fill:#3d0000,stroke:#ff4444,color:#ff8888
    style G fill:#1a3a1a,stroke:#4aff4a,color:#ccc
    style L fill:#0f3460,stroke:#4a9eff,color:#ccc
```

---

## 5. Type Selection as a Decision Function

### Formal model

Let **need(X)** be the set of required operations on a collection X.
The type selection function `τ` maps `need(X)` to the optimal Dart type:

```
τ(need) = argmin_type { cost(type, need) }

where cost(type, need) = Σ complexity(op) for op ∈ need
```

### Decision table (the τ function instantiated)

| need(X) | τ(need) | dominant cost |
|---|---|---|
| lookup only, no order | `HashMap<K,V>` | O(1) amortized |
| lookup + insertion order | `LinkedHashMap<K,V>` (default `{}`) | O(1) amortized |
| lookup + sorted iteration | `SplayTreeMap<K,V>` | O(log n) |
| membership + uniqueness | `HashSet<T>` | O(1) amortized |
| membership + sorted | `SplayTreeSet<T>` | O(log n) |
| ordered + indexed | `List<T>` | O(1) index, O(n) search |
| immutable lookup table | `const Set<T>` | O(1), compile-time |
| named tuple, no behavior | `({T a, U b})` record | stack-allocated |
| fixed variants + owned values | `enum E { ...; T get v }` | compile-time |

**Key theorem:** A value in a `switch` or `Map` key with a fixed domain is **never** optimally represented as a `String`. The optimal type is always `enum` because:
- `String` membership: O(n) character comparison
- `enum` identity: O(1) integer comparison
- `String` exhaustiveness: unverified at compile time
- `enum` exhaustiveness: compiler-enforced (missing case = error)

---

## 6. No Bare Strings — Security Property

### Threat model

claudart is a self-hosted tool. The model reading and optimizing its own source code is an agent with write access. An injection attack is:

```
Attacker: the model's own training distribution
Vector:   bare String literals in command dispatch
Effect:   model substitutes a string matching its own command vocabulary
          rather than the tool's intended command
```

### Formal property

Let `Σ` be the set of all string literals in the codebase.
Let `E` be the set of values owned by enums.
Let `D ⊆ Σ` be the set of "dangerous" strings (values that should be enum-owned).

**Desired property:** `D = ∅`

**Current enforcement:**
- `analysis_options.yaml`: `missing_enum_constant_in_switch: error` — any `switch` on an enum that lacks a case is a compile error
- `prefer_const_declarations: true` — pushes values toward compile-time constants
- `avoid_dynamic_calls: true` — prevents runtime dispatch on untyped values

**Gap:** Dart's built-in lints cannot statically detect `D ≠ ∅` (a string literal that should be an enum value). This requires a `custom_lint` rule. Filed as future work in `analysis_options.yaml`.

**Current risk:** `D` is empirically small — all command names, status values, category labels, and scan scopes are enum-owned. Remaining string literals are user-facing display text, which is not a dispatch surface.

---

## 7. HandoffState — Parse-Once Proof

### Current state (multiple parse calls)

Let `h` be a handoff string of length `n`.
Let `R` be the set of regex patterns applied to `h`.

In the current implementation, each call site independently calls:
```
extractBranch(h)         -- regex on h, O(n)
extractSection(h, 'Bug') -- regex on h, O(n)
extractSection(h, 'Root Cause') -- regex on h, O(n)
...
```

Total cost per command invocation: `O(n × |R|)` where `|R| ≥ 6`.

### Target state (parse-once record)

```dart
typedef HandoffState = ({
  String branch,         // extracted once
  String bug,           // extracted once
  String rootCause,     // extracted once
  HandoffStatus status, // extracted once
});

// O(n × |R|) — paid once at command entry point
final state = parseHandoff(handoff);

// O(1) — field access, no regex
print(state.branch);
print(state.bug);
```

Total cost per command invocation: `O(n × |R|)` paid **once**, then `O(1)` per access.

**Proof of correctness:** Since `h` is immutable within a command invocation (no other process writes to `handoff.md` during execution — claudart is single-threaded), `parseHandoff(h)` is a pure function. The result is referentially transparent: `parseHandoff(h).branch = extractBranch(h)` always. Parsing once is therefore equivalent to parsing many times. ∎

**Implementation status:** Planned as Todo #1. `SessionState` class is the current partial implementation — used in `save.dart` and `rotate.dart` but not yet in `teardown.dart` or `setup.dart`.

---

## 8. WorkspaceConfig — Enum Invariants

### Context window separation

Let **K** be the set of all knowledge files in a workspace. Define two partitions:

```
K_scaffold  =  files compiled into scaffold.md by Agent 1 (/setup)
K_session   =  files loaded per session by Agent 2 (/suggest, /debug)

K_scaffold ∩ K_session = ∅     ← enforced by agent role separation
K_scaffold ∪ K_session ⊆ K
```

**Proof:** Agent 2 reads `scaffold.md` — a single compiled file, not the originals. ∀ f ∈ K_scaffold: Agent 2 never opens f directly. The intersection is empty by construction. ∎

### WorkspaceRole — README update gate

```
∀ workspace w: (w.project.role == WorkspaceRole.maintainer) ↔ (w.canUpdateReadme == true)
```

Enforced by `WorkspaceRole.canUpdateReadme` getter — a `switch` with no default. Adding a new role variant without handling it in `canUpdateReadme` is a compile error.

### StackType — knowledge scope gate

```
∀ f ∈ K_scaffold: ∃ s ∈ workspace.project.stack such that f is relevant to s
```

Enforced at `/setup`: only files listed in `workspace.session.knowledge` are compiled into `scaffold.md`. Files outside that list are never loaded regardless of what exists on disk.

### Enum parse invariant

```
∀ v ∈ workspace.json string values:
  (v ∈ EnumType.validValues) → parsed into typed enum
  (v ∉ EnumType.validValues) → dropped, reported as warning by /setup
```

`fromString` never throws — unknown values return `null` and are excluded from the parsed list. `/setup` reports them so the user can fix `workspace.json`.

### AgentType install invariant

`AgentType.commandTemplate(workspace)` uses an exhaustive `switch` over all variants:

```
∀ v ∈ AgentType.values →
  v.fileName == '${v.name}.md'  ∧  v.commandTemplate(w).isNotEmpty
```

Dart enforcement: the `switch` has no `default` arm — adding a new `AgentType` variant without a corresponding template arm is a compile error (`missing_enum_constant_in_switch: error`). `claudart link` iterates `AgentType.values`; the install loop is closed under the enum.

| Member | Invariant |
|---|---|
| `fileName` | `∀ v → v.fileName == '${v.name}.md'` — bijection between variant and filename |
| `commandTemplate` | Exhaustive switch — `∄ v` with a missing arm at compile time |
| install loop | `∀ v ∈ AgentType.values → fileIO.write(cmdsDir/v.fileName, v.commandTemplate(w))` |

This is I₆ in the invariant table below.

---

### Proof notation enforcement

`ProofNotation.dartGrounded` requires:
- `∀` / `∃` / `∧` / `∨` / `↔` as logical quantifiers in proofs
- Both sides of `↔` must be Dart expressions (not prose)
- `iff` is never used — `↔` with Dart expressions is the replacement
- Every proof cites the Dart mechanism: `const` constructor, null-safety, exhaustive `switch`, `assert()`

---

## 9. Environments and Surfaces

Section 1 describes one session. This section describes every place a session runs: how it is started, how the
project is linked to its workspace, whether the project uses dartrix. Each layer is a typed enum or a getter on one,
checked against the code, so a gap shows up as a failing test or a "no caller yet" row instead of a surprise.

The generated reference is `docs/topology/environments.md` (and `docs/topology/handoff_status.md` for the state
machine); `make topology` rewrites them and a test fails when they go stale.

### 9.1 Layers

| Layer | Typed as | Variants | Verified by |
|---|---|---|---|
| Entry point | `CommandEntry` + `ClaudartCommand.reachedFrom` | `cliSubcommand`, `launcherMenu` (`claudart` with no args), `chatShell` | `claudart_command_test.dart` scans `launch.dart` and `chat_shell.dart` for each call |
| Run mode | `RunMode` + `ClaudartCommand.supportsHeadless` | `interactive`, `headless` (`teardown`, `rotate`, `kill`) | the same test scans each command's source for a `RunMode` parameter |
| Render surface | `ClaudartSurface` | `cli`, `tui` (zedup) | `make consumer-check` (below) |
| Handoff moves | `ClaudartCommand.handoffEvents` | the `HandoffEvent` each command passes | the same test scans `lib/` for each event |
| Link state | `WorkspaceLinkState` + `linkStateOf` | `unlinked`, `symlinked`, `realDirectory` | `workspace_link_state_test.dart`; `launch` and `kill` read it |
| dartrix | the project's pubspec (`detectsDartrixDependency`) | uses, does not use | the lifecycle matrix (below) |
| Consumer | `SessionState.effectiveStatus` | what a reader shows for a handoff | the lifecycle matrix and `make consumer-check` |

claudart is usable on its own: a CLI-only user needs none of zedup. zedup is an optional front end that reads the same
`handoff.md` and calls the same exported API; it must agree with claudart on every status it shows.

### 9.2 What is proven, and where

- **Lifecycle matrix** (`test/conformance`): real commands, in memory, through whole sessions (setup, suggest, debug,
  teardown, kill, rotate, restart), in every environment (3 link states x dartrix on or off = 6). After every step the
  consumer view (`effectiveStatus`), the file and the logged move must agree with an independent literal. The result is
  the same in every environment, which is itself the claim: the lifecycle does not depend on how the project is linked or
  whether it uses dartrix.
- **Consumer check** (`make consumer-check`): replays the same scenarios against zedup's REAL reader in a throwaway copy
  of zedup wired to this checkout (neither repo is modified), and scans zedup for raw-string status writers.

### 9.3 Known gaps (each is a failing check or a visible row, not folklore)

| Gap | Where it shows | Owner |
|---|---|---|
| zedup reads the raw Status line, so a reset session shows as a live one | `make consumer-check`: 4 reader disagreements | zedup: read `SessionState.effectiveStatus` in `parseClaudartHandoff` |
| zedup's TUI writes status as raw strings (`updateStatus`), bypassing validation and `transitions.jsonl` | `make consumer-check`: 2 raw writers (`suggest_coordinator.dart`, `debug_coordinator.dart`); `updateStatus` is now deprecated | zedup: use `applyHandoffEvent` |
| dartrix has no behavioural effect on a session: only `claudart add`'s PLAN stub reads it, and the generated `dependency_config.g.dart` constant has no reader | `environments.md` "dartrix" section | decide: gate something on it, or drop the constant |
| `claudart link` and `unlink` are not in the lifecycle matrix: the link state is a fixture, not an outcome of running them | `lifecycle_scenarios.dart` | add link/unlink scenarios |
| the agent surface (a Claude Code or Cursor slash command running claudart) is not modelled | none yet | add a `CommandEntry` for it once its calls are enumerated |
| 4 handoff events have no code caller (`saveUnconfirmed`, `saveConfirmedExploring`, `debugStarted`, `debugBlocked`): agents make those moves by editing `handoff.md` as the prompts say | `handoff_status.md` "Where each event is passed" | by design today; revisit if claudart should verify them |

### 9.4 Ownership: how the three repos split

Every public component has one owning repo. The owner declares it and tests it (a literal table per variant,
mutation-tested). A consumer tests only its own extensions and its integration with the owner, never the owner's
behavior again. `make ownership` snapshots this into `docs/topology/ownership.md`: components per repo, names declared
in more than one repo, and tests that assert another repo's component behavior.

| Repo | Owns | Consumers must not re-test |
|---|---|---|
| claudart | the session state machine (`HandoffStatus`, `HandoffEvent`, `after`, `effectiveStatus`), the error taxonomy, the model registry (`AgentModel`, `AgentFlow.preferredModel`), `ClaudartCommand` and its entry/headless/event declarations, link state, codegen | any of the above |
| dartrix | the matrix and coverage framework (`Dartrix`, `testSelector`, the shoelace snapshot types) and the paradigm law | its own matrix mechanics |
| zedup | the TUI: its own screens, hotkeys, tool manifests, `kZedupConfig`, its extensions on claudart types (e.g. `AgentFlow.label`) | claudart's types' behavior |

Findings from the first scan, each a tracked gap rather than folklore:

- **Duplicated components:** `ErrorType`, `FailureType`, `FaultClass` and `FaultSeverity` are declared in both claudart
  and zedup (zedup has its own copy of the error taxonomy). One owner: claudart; zedup consumes it (Phase 1 step 8).
- **Misplaced tests, now fixed:** `AgentModel` (alias, slug, shortName, `bestFor*`) and `AgentFlow.preferredModel` were
  tested only in zedup's `claudart_model_test.dart`: the owner did not test its own components. They are now pinned in
  `test/pipeline/agent_model_test.dart` and `agent_flow_test.dart`.
- **Redundant tests, to remove from zedup:** `agent_result_test.dart` asserts `HandoffStatus.expectsDebug`,
  `expectsSuggest` and `fromString` (claudart pins all three per variant); `agent_dispatcher_test.dart` and
  `claudart_model_test.dart` assert `AgentModel.alias` and the `bestFor*` predicates (now pinned here).
- **dartrix knows zedup's variants:** its shoelace test fixtures hard-code zedup's `BranchType` names as strings. The
  framework should stay generic; the fixture should use its own fictional enum.

### 9.5 Environment configuration drives what a user sees

The user's environment (which tools they use, how the project is linked, which agents and stack they chose) should
decide which enums and templates they are exposed to, so they only interface with code that applies to them.

| Where it already works | How |
|---|---|
| zedup | `zedup setup` answers + each tool's manifest generate `kZedupConfig`; the UI exposes only opted-in tools' commands, hotkeys and screens |
| claudart slash commands | `claudart link` writes a command file for each `AgentFlow` with `hasCommandFile`, so the commands a user sees are driven by an enum |

| Where it does not yet | Evidence |
|---|---|
| workspace.json's `session.agents`, `knowledge` and `stack` | written by `claudart link`; read only by the `/setup` agent prompt (an agent following instructions), never by Dart code: the command files `link` generates come from `AgentFlow.values`, not the user's `session.agents` |
| the generated `dependency_config.g.dart` (`usesDartrix`) | no reader; dartrix changes nothing a user sees except `claudart add`'s PLAN stub |

Direction, in dependency order: (1) make workspace.json's selection the input to `claudart link`'s generated command files
(zedup's manifest approach is the model); (2) generate a per-environment registry that exposes only the enabled
components, because a `const bool` cannot gate an import in Dart; (3) have the lifecycle matrix and `make consumer-check`
run in each configuration so the exposed surface is proven, not assumed.

## Summary: The Three Invariants

These are the core invariants claudart enforces. They are not conventions — they are compile-time or runtime proofs.

| # | Invariant | Enforcement | Proof |
|---|---|---|---|
| I₁ | Every state transition is exhaustive | `missing_enum_constant_in_switch: error` | Compiler rejects missing arms |
| I₂ | Every testable behavior has an assertion before session closes | `dart test --test-randomize-ordering-seed=random` + coverage model | `Gap = T − C = ∅` |
| I₃ | No session n+1 begins unless session n's fix compiles | `rotate` build gate | `exitCode = 0` is the only path to new handoff |
| I₄ | scaffold.md and session context are disjoint | Agent role separation — Agent 2 reads `scaffold.md`, never the originals | `K_scaffold ∩ K_session = ∅` by construction |
| I₅ | README updates are gated on workspace ownership | `WorkspaceRole.canUpdateReadme` exhaustive switch | `(role == maintainer) ↔ (canUpdateReadme == true)` |
| I₆ | Every AgentType variant installs its command template | `AgentType.commandTemplate` exhaustive switch + `AgentType.values` loop in `link.dart` | `∀ v ∈ AgentType.values → v.fileName installed ∧ v.commandTemplate(w).isNotEmpty` |
