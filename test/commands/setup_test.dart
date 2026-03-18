import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:claudart/commands/setup.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace   = '/workspaces/my-app';
const _projectName = 'my-app';

// ── Exit helper ───────────────────────────────────────────────────────────────

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

// ── Menu constants ────────────────────────────────────────────────────────────
// _SetupMenu is private in setup.dart — reproduced here so tests use named
// values, not magic numbers.
const _menuResume     = 0;
const _menuStartFresh = 1;
const _menuBack       = 2;

// ── Active handoff fixture ────────────────────────────────────────────────────

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

// ── IO builder ────────────────────────────────────────────────────────────────

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

// ── Prompt helper ─────────────────────────────────────────────────────────────

String? Function(String, {bool optional}) _prompts(List<String?> queue) {
  final iter = queue.iterator;
  return (String _, {bool optional = false}) {
    if (!iter.moveNext()) return null;
    return iter.current;
  };
}

// Standard prompts for a fresh setup — branch, bug, expected, no files, no entry points.
List<String?> get _freshPrompts => [
      'fix/null-ref',
      'Config not loaded when path has spaces.',
      'Config loads regardless of spaces in path.',
      null,
      null,
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {

  // ── Error paths ─────────────────────────────────────────────────────────────

  group('setup — exits 1 when not in a git repo', () {
    test('projectRoot is null without override → exit 1', () async {
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

  group('setup — exits 1 when projectRoot dir does not exist', () {
    test('dirExists false → exit 1', () async {
      // Entry exists in registry but dir is absent from MemoryFileIO.
      const entry = RegistryEntry(
        name: _projectName,
        projectRoot: _projectRoot,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      );
      final io = MemoryFileIO(); // no dirs seeded
      Registry.empty().add(entry).save(io: io);

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

  group('setup — exits 1 when project not in registry', () {
    test('empty registry → exit 1', () async {
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

  // ── Active handoff menu ──────────────────────────────────────────────────────

  group('setup — active handoff → Resume', () {
    test('exits 0', () async {
      final io = _io(handoff: _activeHandoff);
      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => _menuResume,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('handoff unchanged', () async {
      final io = _io(handoff: _activeHandoff);
      try {
        await runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => _menuResume,
          exitFn: _throwExit,
        );
      } on _ExitException {/*expected*/}
      expect(io.read(handoffPathFor(_workspace)), equals(_activeHandoff));
    });
  });

  group('setup — active handoff → Back', () {
    test('exits 0', () async {
      final io = _io(handoff: _activeHandoff);
      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => _menuBack,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('handoff unchanged', () async {
      final io = _io(handoff: _activeHandoff);
      try {
        await runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: (_) => _menuBack,
          exitFn: _throwExit,
        );
      } on _ExitException {/*expected*/}
      expect(io.read(handoffPathFor(_workspace)), equals(_activeHandoff));
    });
  });

  group('setup — active handoff → Start fresh', () {
    test('falls through and writes new handoff', () async {
      final io = _io(handoff: _activeHandoff);
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => _menuStartFresh,
        exitFn: _throwExit,
      );
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Config not loaded when path has spaces.'));
      expect(handoff, isNot(equals(_activeHandoff)));
    });
  });

  // ── New handoff written ──────────────────────────────────────────────────────

  group('setup — writes handoff on confirm', () {
    test('contains bug text', () async {
      final io = _io();
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('Config not loaded when path has spaces.'),
      );
    });

    test('contains expected behavior text', () async {
      final io = _io();
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('Config loads regardless of spaces in path.'),
      );
    });

    test('contains project name in header', () async {
      final io = _io();
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('# Agent Handoff — $_projectName'),
      );
    });

    test('contains files when provided', () async {
      final io = _io();
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'fix/null-ref',
          'Config not loaded when path has spaces.',
          'Config loads regardless of spaces in path.',
          'lib/config/loader.dart',
          null,
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('lib/config/loader.dart'),
      );
    });

    test('contains entry points when provided', () async {
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
          'ConfigLoader.load',
        ]),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('ConfigLoader.load'),
      );
    });

    test('logger writes interaction entry after successful setup', () async {
      final io = _io();
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      final logsPath = p.join(logsDirFor(_workspace), 'interactions.jsonl');
      final raw = io.read(logsPath);
      expect(raw, isNotEmpty);
      final entry = jsonDecode(raw.trim().split('\n').last) as Map<String, dynamic>;
      expect(entry['command'], equals('setup'));
      expect(entry['outcome'], equals('ok'));
    });
  });

  // ── Cancelled ────────────────────────────────────────────────────────────────

  group('setup — cancelled when user declines confirm', () {
    test('exits 0', () async {
      final io = _io();
      await expectLater(
        runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts(_freshPrompts),
          pickFn: (_) => 0,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('no handoff written — verified against pre-seeded handoff', () async {
      // Pre-seed a handoff so the assertion can actually fail if setup writes.
      final io = _io(handoff: _activeHandoff);
      // Simulate: fresh io with active handoff, pick Start fresh, then decline.
      try {
        await runSetup(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts(_freshPrompts),
          pickFn: (_) => _menuStartFresh,
          exitFn: _throwExit,
        );
      } on _ExitException {/*expected*/}
      // If setup wrote a new handoff, this would not equal _activeHandoff.
      expect(io.read(handoffPathFor(_workspace)), equals(_activeHandoff));
    });
  });

  // ── sensitivityMode = false ───────────────────────────────────────────────────

  group('setup — sensitivityMode false', () {
    test('handoff written as plain text without abstraction', () async {
      final io = _io(sensitivityMode: false);
      await runSetup(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_freshPrompts),
        pickFn: (_) => 0,
        exitFn: _throwExit,
      );
      expect(
        io.read(handoffPathFor(_workspace)),
        contains('Config not loaded when path has spaces.'),
      );
    });
  });
}
