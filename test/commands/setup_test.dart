import 'package:test/test.dart';
import 'package:claudart/commands/setup.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';
const _projectName = 'my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

/// Builds a [MemoryFileIO] with a registry entry and the project root dir
/// registered. [handoff] is optional — if provided it is written to the
/// workspace handoff path.
MemoryFileIO _io({String? handoff, bool sensitivityMode = false}) {
  final entry = RegistryEntry(
    name: _projectName,
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
    sensitivityMode: sensitivityMode,
  );
  final io = MemoryFileIO(
    dirs: {_projectRoot},
    files: {
      if (handoff != null) handoffPathFor(_workspace): handoff,
    },
  );
  Registry.empty().add(entry).save(io: io);
  return io;
}

/// Returns preset answers from [queue] in order. Returns null once exhausted.
String? Function(String, {bool optional}) _prompts(List<String?> queue) {
  final iter = queue.iterator;
  return (String _, {bool optional = false}) {
    if (!iter.moveNext()) return null;
    return iter.current;
  };
}

// Active handoff fixture — has real content so setup shows the existing-session
// menu.
const _activeHandoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-16 | Branch: fix/null-ref

---

## Status

suggest-investigating

---

## Bug

Config not loaded when path has spaces.

---

## Expected Behavior

Config loads regardless of spaces in path.

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### Key entry points in play
_Not yet determined._

### Classes / methods in play
_Not yet determined._

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

void main() {
  // ── Error paths ───────────────────────────────────────────────────────────

  group('setup — exits 1 when not in a git repo', () {
    test('exits 1 when projectRootOverride is null and no git context', () async {
      // Without projectRootOverride and without a real git repo, detectGitContext
      // returns null → exit(1). We call with no override so projectRoot is null.
      final io = MemoryFileIO();
      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: null,
          confirmFn: (_) => false,
          promptFn: _prompts([]),
          pickFn: (_) => 0,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });

  group('setup — exits 1 when no registry entry found', () {
    test('exits 1 when project is not registered', () async {
      // Empty registry — no entry for _projectRoot.
      final io = MemoryFileIO(dirs: {_projectRoot});
      Registry.empty().save(io: io);

      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts([]),
          pickFn: (_) => 0,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });

  // ── Existing active handoff ───────────────────────────────────────────────

  group('setup — active handoff menu', () {
    test('exits 0 when user picks Continue (index 0)', () async {
      final io = _io(handoff: _activeHandoff);

      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => 0, // Continue
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('exits 0 when user picks Back (index 2)', () async {
      final io = _io(handoff: _activeHandoff);

      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => 2, // Back
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('handoff unchanged when user picks Continue', () async {
      final io = _io(handoff: _activeHandoff);

      try {
        await runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => 0, // Continue
          exitFn: _throwExit,
        );
      } on _ExitException {
        // expected
      }

      expect(io.read(handoffPathFor(_workspace)), equals(_activeHandoff));
    });
  });

  // ── New handoff written ───────────────────────────────────────────────────

  group('setup — writes handoff on confirm', () {
    test('writes handoff file with correct bug and expected when confirmed',
        () async {
      final io = _io();

      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',  // branch (since gitCtx is null with override)
          'Config not loaded when path has spaces.',  // bug
          'Config loads regardless of spaces in path.',  // expected
          null,  // files — optional, skip
          null,  // entry points — optional, skip
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );

      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Config not loaded when path has spaces.'));
      expect(handoff, contains('Config loads regardless of spaces in path.'));
    });

    test('handoff contains project name in header', () async {
      final io = _io();

      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',
          'Config not loaded when path has spaces.',
          'Config loads regardless of spaces in path.',
          null,
          null,
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );

      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('# Agent Handoff — $_projectName'));
    });

    test('handoff includes files section when files provided', () async {
      final io = _io();

      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',
          'Config not loaded when path has spaces.',
          'Config loads regardless of spaces in path.',
          'lib/config/loader.dart',  // files provided
          null,  // entry points — skip
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );

      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('lib/config/loader.dart'));
    });

    test('handoff includes entry points when entry points provided', () async {
      final io = _io();

      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',
          'Config not loaded when path has spaces.',
          'Config loads regardless of spaces in path.',
          null,  // files — skip
          'ConfigLoader.load',  // entry points provided
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );

      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('ConfigLoader.load'));
    });
  });

  // ── Cancelled ─────────────────────────────────────────────────────────────

  group('setup — cancelled when user declines confirm', () {
    test('exits 0 when user declines confirm', () async {
      final io = _io();

      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,  // decline
          promptFn: _prompts([
            'fix/null-ref',
            'Config not loaded when path has spaces.',
            'Config loads regardless of spaces in path.',
            null,
            null,
          ]),
          pickFn: (_) => 0,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('no handoff written when user declines confirm', () async {
      final io = _io();

      try {
        await runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts([
            'fix/null-ref',
            'Config not loaded when path has spaces.',
            'Config loads regardless of spaces in path.',
            null,
            null,
          ]),
          pickFn: (_) => 0,
          exitFn: _throwExit,
        );
      } on _ExitException {
        // expected
      }

      expect(io.fileExists(handoffPathFor(_workspace)), isFalse);
    });
  });

  // ── Sensitivity scan skipped ──────────────────────────────────────────────

  group('setup — sensitivity scan skipped when sensitivityMode=false', () {
    test('handoff written without scan when sensitivityMode is false', () async {
      // sensitivityMode=false → no scan is triggered. The handoff is written
      // directly without abstraction. Verify the plain content is preserved.
      final io = _io(sensitivityMode: false);

      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',
          'Config not loaded when path has spaces.',
          'Config loads regardless of spaces in path.',
          null,
          null,
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );

      final handoff = io.read(handoffPathFor(_workspace));
      // Content is written as-is (not abstracted) since sensitivityMode=false.
      expect(handoff, contains('Config not loaded when path has spaces.'));
    });
  });
}
