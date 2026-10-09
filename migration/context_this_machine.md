# Context exchange — this machine

Working artifact for the cross-machine claudart sync effort. Not part of the
backup feature itself — a shared scratch space so both sides write down what
they actually have before designing the real `backup`/`restore` commands
against guesses. Delete this whole `migration/` directory once that feature
ships for real (same "ship it, delete it" convention as `portability_gap.dart`).

Add your machine's equivalent file alongside this one — don't edit this file,
add `context_other_machine.md` (or similar) next to it. The diff between the
two is the actual spec for what the backup feature needs to reconcile.

## Design constraint, explicit: no env-var-dependent migration

This machine happens to set `CLAUDART_WORKSPACE` to redirect the workspace
root away from the default `~/.claudart`. That is a per-machine convenience,
not something the other machine has or should need. Whatever `backup`/
`restore` ends up being, it must not assume both machines agree on
`CLAUDART_WORKSPACE`, or any other env var, pointing at the same place —
it should work off whatever `workspacesRoot` resolves to *locally* on each
side (default or overridden), never require the override itself to match.

## Generic knowledge inventory (`knowledge/generic/`)

Resolved root here: `~/dev/dev_tools/claude/knowledge/generic/` (because of
the `CLAUDART_WORKSPACE` override above — ignore the absolute path, only the
relative shape and contents matter).

| file | lines | sha256 |
|---|---|---|
| agent-architecture.md | 81 | a3eb3d70e5b34bc17f11c37b5236394d38fd86c824901e301a9f8460ce143416 |
| bloc.md | 37 | b4028e1b762078a8e835fed5c72e6c2e1e0e2c0365eabf34efa1374d1590e4a8 |
| dart_flutter.md | 36 | 82614c0688c445561ae800251bd6bb08998a135576820b42ba45b00103f8dda0 |
| enum-vs-variable.md | 124 | b7481186b9ac07bd381fa8e29e57767ccd43b27937bc11fcc9bb759a03fcf037 |
| git-authorship.md | 23 | d75d7f457b07c879956869791c3c60c91ca88410e83d6c641feac73ae9965895 |
| privacy_abstraction.md | 135 | d5753b09156b448564aee16eb12a8fa1ed60d93ef1eab604c85a9d6afa0e87a5 |
| riverpod.md | 32 | bb62d864a8cf91da44b5fd6ba1294e76dbd165cdc6045b49d23c7b826b0c2ce5 |
| testing.md | 47 | 59e3b6d1b13361dd560ef7a97fd057f1818413742dd48d8f3127b73ef5b291fc |
| workspace-config.md | 64 | 1eaa6da14fac799a0d74f81266eb1de18d54037c36730a830ada5e13add330a3 |

Note: **no `code.md` and no `dart.md` exist here** — only `dart_flutter.md`.
`lib/knowledge_templates.dart`'s `codeTemplate`/`dartTemplate`/
`testingTemplate` are defaults `init` never actually writes to disk (see
`lib/commands/init.dart` — it writes starter `dart.md`/`testing.md`, not
`code.md`, and this machine's `dart_flutter.md` predates and diverges from
whatever `init` would generate today). No math/proof-notation rules live in
any knowledge file — proof notation is a `workspace.json` *setting*
(`session.proofNotation`), not a knowledge doc; see below.

## Per-project config shape (`workspace.json`, example from `claudart` itself)

```json
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
```

Each project's `workspace.json` references a *subset* of the shared generic
pool by name (`session.knowledge`), resolved at session-start against
`knowledge/generic/<name>.md`. `proofNotation: "dart-grounded"` is the same
across every project on this machine — it's what the `setup-claudart` skill
compiles into `scaffold.md` as "use ∀/∃/∧/∨/↔ with Dart expressions." This is
config, small, portable, no absolute paths inside it except none — safe to
carry as-is.

## What actually loads into the model prompt

Not Dart runtime logic — the generated `.claude/commands/*.md` skill files
(`lib/templates/suggest_template.dart`, `debug_template.dart`,
`setup_template.dart`, `teardown_template.dart`) hardcode the knowledge file
paths as plain instruction text at generation time
(`claudart link`/`claudart init`), using `paths.dart`'s `genericKnowledgeDirFor`/
`projectsKnowledgeDirFor` getters. **PR #40** (already open on `main`, not
merged) fixes a real mismatch here: the installed templates pointed at paths
`init` never actually writes to. Read that PR before designing `BackupItem`
around the knowledge-path problem — it may already be solved by the time
backup/restore lands.

## Already exchanged, for context

Three ad hoc zips (plain `zip`, not a claudart feature) moved `skills.md` +
`knowledge/projects/*.md` for zedup, dartrix, dc-flutter to the other
machine already, by hand. This file + its sibling are meant to replace that
manual process with a real design, not duplicate what's already moved.
