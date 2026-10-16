# Brief decomposition — "Template-Driven Architecture" (2026-10-12)

Source: owner's Agent Brief (templates at the center; claudart, zedup, dartrix).
Status: DECOMPOSED ONLY. The brief says stop after Phase 1 and report; no implementation until approved.
Relation to earlier work: this brief SUPERSEDES the slice order in `plan.md`. Architecture first, then fit the
ledger's gaps into it. `ledger.md` stays valid as the gap inventory (each gap gets a home below).

## 0. Layer model (owner clarification, 2026-10-12): "templates" has layers. Layers are named by owning tool + purpose, never L-numbers.

The brief's word "template" covers TWO layers (the claudart handoff template, and the per-env codegen above it). Brief P1 must keep them apart.

| Layer (tool + purpose) | What it is | Source of truth today | Exists in code? |
|---|---|---|---|
| **claudart workspace.json tool-selection config** (+ zedup setup answers) | which tools the user uses (claudart, zedup, dartrix/shoelace) and each one's configuration | `workspace.json`, pubspec detection (`detectsDartrixDependency`), zedup setup answers + tool manifests | three separate sources, no single owner |
| **claudart-link / zedup-setup codegen of per-env Dart** | Dart generated per env setup; the user is exposed only to code available for their tools | claudart `lib/generated/dependency_config.g.dart` (one bool, `usesDartrix`); zedup `lib/src/generated/user_config.g.dart` (`kZedupConfig`: bindings, commands, hotkeys, screens, integrations, coverageAxes) | yes, both; claudart's is minimal |
| **dartrix matrix (coverage cells per variant x feature)** | cells set per user's usage, derived from the codegen above (zedup manifests already declare `coverageAxes`) | dartrix `Dartrix`/`testSelector`; claudart `test/matrix/*` | partial; not derived from the codegen |
| **claudart handoff template (work-type contract)** | handoff sections, transitions, tools/skills per state, expectations (the brief's `WorkType`) | `handoff_template.dart`, `HandoffStatus`, `AgentCategory` | bug-shaped only; no `WorkType` |
| **claudart handoff.md session state** | one handoff instance, updated async by claudart/zedup/dartrix | `handoff.md`, `SessionState` | yes |
| **claudart pipeline agent run + logging** | tool calls chosen from the handoff template within what the codegen exposes; expected-vs-actual logged | pipeline, `SessionLogger`, `PlannerLog` | partial |

Dependency direction: tool-selection config -> per-env codegen -> dartrix matrix and handoff template; the handoff template
is resolved inside what the codegen exposes (a tool absent from the env is never offered by a template getter). Session
state and the agent run read the handoff template.

Answer to "can a template generate Dart files from that layer": yes, both repos already do it with the same pattern
(pure renderer + injectable `GeneratedFileWriter`, run at `claudart link` / `zedup setup`). The gap is that claudart's
per-env codegen is a single bool, and the doc comment on `usesDartrix` says it gates dartrix types but only `plan_template.dart` and
`add.dart` read it. [V]

Constraint found: a `const bool` cannot gate an import in Dart. To make the user "locked into only the code available
per tool-env setup", the per-env codegen must generate a registry/barrel that imports only enabled tools' modules (zedup's
`kZedupConfig.bindings` is the model), not flags. Performance claim to test, not assume: gain is mainly exposure and
compile-time narrowing; measure before promising speed. claudart already has `claudart compile`; zedup chains
`dart compile exe` after setup, so the regenerate-then-recompile path exists for both.

Duplicate to consolidate: `GeneratedFileWriter` typedef and the default writer are copied in both codegens. [V]
Overlap: tool selection has three sources (workspace.json, pubspec detection, zedup setup answers).

## 1. Classification (claudart taxonomy)

| Item | Category | Intent | Complexity | Preferred model (routeModel) |
|---|---|---|---|---|
| Whole brief | research -> feature | design | systemic | opus |
| Phase 0.5 logging audit | research | analyze | compound | sonnet (analyze) |
| Phase 1 research (8 deliverables) | research | analyze | systemic | opus |
| Phase 2 architecture proposal | feature | design | systemic | opus |
| Implementation (after approval) | refactor/feature | implement | per slice | sonnet |

Naming collision: the brief's "Phase 1/2" are NOT PLAN.md's roadmap phases (v1, v2, template system Phase 2, ...).
Refer to them as "Brief P1 / Brief P2" in handoffs. Also note PLAN.md's Phase 2 is already a "template system";
Brief P1 must report whether they are the same work.

## 2. Decomposition by dimension

### Intent
Define the architecture first with a typed template (enhanced enum / sealed type) as the contract for each work
type; fit existing gaps into it; make code and design agree. Nothing new is required.

### Features (what must exist at the end)
- `WorkType` enhanced enum (bug, feature, refactor, research, audit, ...) whose getters answer: sections,
  valid transitions, scope, tools per state, skills per state, codegen targets, matrix cells, expected outcomes.
- Layered codegen driven by the template.
- Tool/skill dispatch chosen by code from state, not prompt prose.
- Topology skill (dartrix + claudart) carried in every handoff.

### State
- Lifecycle: setup -> read env -> init state -> validate not stale -> cache -> select template from intent -> getters
  scope everything -> agents run -> async user changes (claudart CLI, zedup TUI, dartrix runs) -> getters re-resolve.
- Evaluate a sealed state machine; evaluate whether the existing "mutation" pattern maps (needs clarification, see 5).
- Open: what makes cached state stale; typed handoff-metadata schema.

### Logging (Phase 0.5, runs first and stays on)
- One flag, always true while working. Do not create one. Existing: `--debug`/`CLAUDART_DEBUG=1`
  (`lib/pipeline/debug_mode.dart`, `CLAUDART_DEBUG_PATH`), `SessionLogger` (`lib/logging/logger.dart`),
  `PlannerLog` (`lib/logging/planner_log.dart`).
- Each entry records expected vs actual; mismatches flagged. Decide where "expected" lives (template getter,
  matrix cell, or test).
- Typed: enhanced enums for kind/level, sealed entry types; failures through the existing Exception/ErrorType/
  FailureType path; one entry point; flag in state so templates, agents, mocks read the same value.
- Audit questions: which layers honor it, read-once vs re-read, visible/settable from zedup and dartrix.

### Audits (Brief P1 deliverables)
D1 layer map matrix; D2 init trace with real debug output; D3 template readiness per work type;
D4 drift report (which side is stale); D5 overlap list; D6 string/flag inventory; D7 test redundancy;
D8 logging audit with real `--debug` sample.

### Gaps
Existing gaps are not dropped; each maps into the architecture (see section 3).

### Testing
- Tests built from state (mocks fed from typed state; expects on typed values), matrix-driven variants, redundancy
  collapsed (D7). dartrix matrices drive proof once the flow works. Mutation testing relevance to be assessed.

### Dart principles (constraints on every deliverable)
Readable; enhanced enums for closed sets; deliberate sealed/abstract/mixin/implements with justification;
exhaustive switch, no stringly dispatch; existing error types; everything flows into state; reuse before adding.

### Orchestration
claudart plans the audit across subagents with explicit dependencies (section 4).

## 3. Where the existing ledger gaps land

| Ledger | Home in the brief |
|---|---|
| A1-A6 untyped status writes, no transition function | D4 drift + D6 inventory; becomes the template's transition getter (Brief P2 State) |
| A2 `debug-in-progress` never written; A3 `flow` writes `ready-for-suggest` | D3 template readiness (transitions) |
| B1-B8 test honesty | D7 + Testing |
| C layering violations | D1 layer map |
| D1, D2, D5 zedup duplicates and pin drift | D1, D5 overlap list |
| D3 zedup runner hardcodes skip-permissions | D4 drift; tool-per-state dispatch |
| D4 zedup generators with no callers | D3 codegen targets |
| D7 three snapshot models | D5 overlap list |
| E docs vs code | D4 drift |
| F dead/test-only code | D5 overlap / D6 |
| G invisible flow decisions | Phase 0.5 / D8 |
| H naming | D6, last |
| Issues #87, #85, #83, #82, #81, #79, #77, #76, #75, #56 | after approval; #87 (routing) folds into tool/skill per-state dispatch |

## 4. Orchestration plan for Brief P1 (read-only, debug flag on)

Dependencies explicit; ledger evidence is reused so agents verify, not rediscover.

| Step | Work | Needs | Agent |
|---|---|---|---|
| 0 | Turn debug flag on for every run; capture real `claudart --debug setup` output | - | coordinator |
| 1a | Logging audit (D8) across claudart/zedup/dartrix | 0 | audit-logging |
| 1b | Initialization trace (D2): `setup.dart`, `link.dart`, `workspace_config.dart`, `registry.dart` with real run | 0 | audit-init |
| 1c | State/handoff audit: `HandoffStatus`, 9-section `handoff_template.dart` universal vs bug-only, `AgentCategory` vs WorkType, metadata schema | ledger A | audit-state |
| 1d | Codegen + matrix audit: `lib/codegen/`, `test/matrix/*`, dartrix model (D3 codegen/matrix columns, D7) | ledger B | audit-matrix |
| 1e | zedup consumption audit: types consumed, async triggers, handoff-shape assumptions | ledger D | audit-zedup |
| 2 | Synthesis: D1 layer matrix, D3 readiness, D4 drift, D5 overlap, D6 inventory, answers to the 5 open questions | 1a-1e | coordinator |
| 3 | Independent Opus review of the report (claims verified against code) | 2 | reviewer |
| STOP | Report to owner; no implementation until approved | 3 | owner |

Constraints on agents: read-only, no concurrent mutation runs, worktrees removed afterward, claims marked verified/unverified.

## 5. Questions the brief leaves open (need owner's word)

1. "Mutation pattern" and "mutation testing" in the State section: which do you mean - `mutation_test` source mutation,
   or state-change events? Research will examine both unless told otherwise.
2. Is PLAN.md Phase 2 (template system) the same work as this brief's template system? Assumed yes (merge them).
3. Does "audit" as a work type include the kind of work this coordinator session is doing? Assumed yes.
4. Branch `feat/mutation-runner-streams` (2 local commits): push now, or hold until after approval?

## 6. Partial answers already known (from the audits; still to be re-verified under the debug flag)

- Open Q5 (prior audit): findings are `ledger.md`; open items are all of it - nothing is fixed yet except
  what is merged (#84, #86). `design.md:62` (exhaustive delta) is stale vs code.
- Template readiness today: `handoff_template.dart` has 9 sections (Status, Bug, Expected, Root Cause, Scope,
  Constraints, Debug Progress, Suggest Resume Notes, Pending Issues); bug-shaped by name; no WorkType exists.
- `AgentCategory` has 6 variants (feature, bug, refactor, research, setup, gui), no `audit`.
- Debug flag exists as env var + CLI flag in `debug_mode.dart`; `SessionLogger` is used in scan/doctor/setup only
  (audit claim); `PlannerLog` recorded only by `flow` (audit claim).

## 7. Added requirement (owner, 2026-10-12): shared-enum dependency change -> handoff state -> downstream scaling/testing

When a shared enum changes (a variant added/removed/renamed, or a getter's value changed), that change sets state on the
handoff object. The handoff then tells the agent which dependent projects must scale or test where those properties are
used in their own usages.

How it maps onto what exists (all [V] unless noted):
- Same pattern as `ArtifactState`/`stateOf` (lib/codegen/artifact_state.dart): render the expected value, diff against
  what is recorded, report fresh/stale. No persisted lock needed beyond a recorded fingerprint.
- dartrix already models the downstream half: a new variant becomes a gap cell in every consumer's matrix until a test
  covers it (`Dartrix.gaps()`), so "test where used" is the matrix reporting uncovered cells.
- Today nothing detects it: zedup pins claudart 33 commits behind and its version guard (exact `2.0.0` match) cannot see
  drift; zedup hand-lists enums for its matrix. [V]

Proposed shape (for Brief P2 approval):
1. A typed registry of shared enums (e.g. `HandoffStatus`, `AgentFlow`, `AgentModel`, `FaultClass`, `ErrorType`): owner repo,
   consumer repos, and a fingerprint of variant names (+ the getters that matter).
2. The per-env codegen (claudart-link / zedup-setup) records each consumer's last-seen fingerprint.
3. Comparison on link/setup/launch/doctor: mismatch emits a typed event and writes a handoff section
   (`HandoffSection.downstreamImpact`): changed enum, change kind, consumer repo, usage sites (analyzer references), and
   the dartrix cells that are now gaps. Status moves through the typed phase transition, not a string write.
4. The agent reads that section and scopes the next session to the consumers.

Open questions: who owns the registry (claudart, or dartrix since both consumers depend on it); fingerprint by variant
names only or also getter values; usage sites by analyzer vs grep; does a downstream-impact state block commits or only warn.

## 8. Added requirement (owner, 2026-10-12): per-variant reference index ("where is this used, in every layer")

Every shared enum variant exposes a getter listing everywhere it is mentioned, across all layers: code, tests, handoff
markdown, skill markdown, command templates, comments, docs, generated files. Goal: the enum is the 1:1 anchor, so an agent
triages scope and usage from code, not from prose.

Design constraints and shape (for Brief P2 approval):
1. Each variant declares its mention forms (a getter): Dart identifier, qualified name, wire value (`ready-for-debug`),
   command/file name (`debug-<project>.md`). Mentions in markdown use wire forms, so identifier search alone misses them.
2. A shared mixin on enums (e.g. `mixin Referenceable on Enum`) owns `mentionForms` and `references`; a typed
   `Reference(layer, path, line, kind)` where `layer` is the named layer (claudart handoff template, dartrix matrix, ...).
   One generic typedef/class for the index result so every enum shares the same shape; no per-enum copies.
3. The index is a build-time artifact produced by the per-env codegen and staleness-checked with the `stateOf` pattern
   (not computed at runtime; an enum cannot see its own usages at runtime).
4. 1:1 check runs both ways: every mention resolves to a variant (a mention of `suggest-needed`, which matches no variant
   and was a real bug found in `suggest_template.dart:52`, is flagged as stale) and every variant is mentioned where its
   layer expects it (a variant with no test = dartrix gap cell).
5. Feeds section 7: a shared-enum change lists its references as the downstream-impact scope.

Reuse before adding: `tool/check_test_only_symbols.dart` (census), `tool/check_duplicate_literals.dart` and the analyzer
already scan usage; extend or replace them with this index rather than adding a fourth scanner.

Limits: code references can be exact (analyzer resolves elements); markdown/comment mentions are token matches, so they
catch the wire form and name but not paraphrase, and may false-positive on common words (a variant named `test`). 1:1 is
achievable for tokens, not for meaning. Start with one enum (`HandoffStatus`) as the single real consumer before generalizing.

Open questions: which mention forms are mandatory per enum; is the analyzer package an acceptable dev dependency for the
index tool; do generated files count as references or are they excluded.
