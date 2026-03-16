# Changelog

## 1.0.0

Initial release.

- `claudart` interactive launcher — lists workspace projects, routes into setup workflow
- `claudart init` — scaffolds workspace with generic Dart/Flutter/BLoC/Riverpod/testing knowledge
- `claudart init --project <name>` — creates project-specific knowledge file
- `claudart link` — symlinks workspace into project, reads `pubspec.yaml` to embed SDK constraints in `CLAUDE.md`
- `claudart unlink` — removes workspace symlinks cleanly
- `claudart setup` — prompts for bug context, writes `handoff.md`
- `claudart status` — prints active handoff state
- `claudart teardown` — classifies session learnings, archives handoff, suggests commit message
- `FileIO` and `ProcessRunner` interfaces for testable I/O injection
- `MemoryFileIO` and `mocktail`-based mocks for unit testing without disk access
