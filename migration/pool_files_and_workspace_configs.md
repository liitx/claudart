# Pool files + workspace.json inventory — this machine

Delivered here (commit, not chat) instead of a manually-relayed zip, per the
user's explicit "so I don't have to play messenger." Labels: VERIFIED = read
directly from disk on this machine, 2026-10-08.

## dart_flutter.md (VERIFIED)

1082 bytes, sha256 `82614c0688c445561ae800251bd6bb08998a135576820b42ba45b00103f8dda0`
(matches what's already in `context_this_machine.md`). No company-internal
content — safe to paste verbatim.

```
# Generic Dart / Flutter Practices
> Flutter 3.32.5 | Dart 3.8.1
> Updated by claudart teardown. Do not edit manually.

## Dart
- Prefer `const` constructors wherever possible
- Use `sealed` classes for exhaustive pattern matching over enums with behaviour
- Avoid `dynamic` — use generics or `Object?` with type checks
- Prefer named parameters for functions with more than two arguments
- Use `extension` types to wrap primitives with domain meaning
- `late` is a smell — prefer nullable or required initialisation

## Flutter
- Never import `material` or `cupertino` directly — use `flutter/widgets.dart`
- Prefer `const` widgets to minimise rebuild scope
- Widget build methods should contain zero logic — extract to methods or classes
- Use `Key` types (`ValueKey`, `ObjectKey`) deliberately; avoid random keys
- Avoid `setState` inside `initState` — use `WidgetsBinding.addPostFrameCallback`

## State management
See `bloc.md` and `riverpod.md` for pattern-specific guidance.

## Patterns to avoid
_Populated by teardown from real sessions._
```

## workspace.json — one per project (VERIFIED)

`dlt-viewer` has no workspace on this machine — nothing to include.

`dc-flutter`'s real work email is redacted below (`[REDACTED]`) — company-
internal, not safe to commit verbatim to a shared repo. The `digital-cockpit`
org name and Toyota-distinct identity shape are kept since that distinction
(liitx vs. toyota org identity, confirmed earlier this session) is itself
load-bearing context, not sensitive on its own.

```json
// claudart/workspace.json
{
  "owner": {"name": "Aksana Buster", "email": "ab@liitx.com", "handle": "liitx"},
  "project": {"name": "claudart", "stack": ["dart"], "repo": "https://github.com/liitx/claudart", "role": "maintainer"},
  "session": {
    "agents": ["suggest", "debug", "save", "teardown"],
    "knowledge": ["dart_flutter", "testing", "enum-vs-variable", "git-authorship"],
    "proofNotation": "dart-grounded",
    "sensitivityMode": true
  }
}

// zedup/workspace.json
{
  "owner": {"name": "Aksana Buster", "email": "ab@liitx.com", "handle": "liitx"},
  "project": {"name": "zedup", "stack": ["dart"], "repo": "https://github.com/liitx/zedup", "role": "maintainer"},
  "session": {
    "agents": ["suggest", "debug", "save", "teardown"],
    "knowledge": ["dart_flutter", "testing", "enum-vs-variable", "git-authorship"],
    "proofNotation": "dart-grounded",
    "sensitivityMode": false
  }
}

// dartrix/workspace.json
{
  "owner": {"name": "Aksana Buster", "email": "ab@liitx.com", "handle": "liitx"},
  "project": {"name": "dartrix", "stack": ["dart"], "repo": "https://github.com/liitx/dartrix", "role": "maintainer"},
  "session": {
    "agents": ["suggest", "debug", "save", "teardown", "flow"],
    "knowledge": ["dart_flutter", "testing", "enum-vs-variable", "git-authorship"],
    "proofNotation": "dart-grounded",
    "sensitivityMode": false
  }
}

// dc-flutter/workspace.json
{
  "owner": {"name": "Aksana Buster (TMS)", "email": "[REDACTED]", "handle": "aksana.buster"},
  "project": {"name": "dc-flutter", "stack": ["dart", "flutter", "bloc"], "org": "digital-cockpit", "role": "contributor"},
  "session": {
    "agents": ["suggest", "debug", "save", "teardown"],
    "knowledge": ["dart_flutter", "bloc", "riverpod", "testing", "enum-vs-variable", "git-authorship"],
    "proofNotation": "dart-grounded",
    "sensitivityMode": false
  }
}
```

## Remaining 8 pool files (not pasted here — large, low-risk to hand over as real files instead of inline text)

`agent-architecture.md`, `bloc.md`, `enum-vs-variable.md`, `git-authorship.md`,
`privacy_abstraction.md`, `riverpod.md`, `testing.md`, `workspace-config.md` —
hashes already listed in `context_this_machine.md`. Ask directly if inline
text is actually needed for any of these; pasting all 8 here would bloat this
doc for little benefit over the hash-verified inventory already committed.
