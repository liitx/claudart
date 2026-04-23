# Retired: AgentType enum

**Retired in:** _(pending commit hash)_
**Date:** 2026-04-21

## What was removed

- `enum AgentType` from `lib/workspace/workspace_config.dart` — variants: setup, suggest, debug, save, teardown
- Import of 5 command template functions from workspace_config.dart
- `WorkspaceSession.agents` typed as `List<AgentType>` → `List<AgentFlow>`

## Why

`AgentType` duplicated `AgentFlow` with a narrower scope. It lacked model preferences,
step lists, and pipeline routing — the concerns `AgentFlow` was built for.
Retaining two enums for the same set of named workflow variants violated the
single-source-of-truth rule and would have required both to be updated on every
new flow addition.

## What replaced it

`AgentFlow` from `lib/pipeline/agent_flow.dart`, extended with:
- `hasCommandFile` — declares whether a flow installs a slash command .md
- `commandTemplate(workspacePath)` — exhaustive switch over all variants
- `fileName` — `'$name.md'`
- `teardown` variant added to `AgentFlow`

`workspace_config.dart` now imports `AgentFlow` directly.
`link.dart` iterates `AgentFlow.values.where((f) => f.hasCommandFile)`.

## Key insight

When an enum starts growing attributes that belong to another enum, the right move
is to merge them — not add a bridge. Two enums that name the same concepts will
always drift. One enum with orthogonal fields (pipeline steps, model tier, command file)
stays coherent across extensions.
