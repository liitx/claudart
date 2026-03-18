import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/save.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';

// Handoff with root cause confirmed and files changed.
const _fullHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: fix/null-ref

---

## Status

ready-for-debug

---

## Bug

Config not loaded when path has spaces.

---

## Expected Behavior

Config loads regardless of spaces in path.

---

## Root Cause

ConfigLoader splits path on spaces before resolving.

---

## Scope

### Files in play
lib/config/loader.dart

### Key entry points in play
ConfigLoader

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
Traced call through config loader.

### What changed (files modified)
lib/config/loader.dart — added path quoting.

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

// Handoff with root cause NOT confirmed.
const _unconfirmedHandoff = '''# Agent Handoff — my-app

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

// Handoff with root cause confirmed but no changed files.
const _confirmedNoFilesHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: main

---

## Status

ready-for-debug

---

## Bug

Parser returns empty on malformed input.

---

## Expected Behavior

Parser returns null or throws on malformed input.

---

## Root Cause

Missing null guard before JSON decode.

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

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

MemoryFileIO _io({String handoff = _fullHandoff}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final io = MemoryFileIO(
    files: {handoffPathFor(_workspace): handoff},
  );
  Registry.empty().add(entry).save(io: io);
  return io;
}

List<String> _checkpoints(MemoryFileIO io) => io.files.keys
    .where((k) =>
        k.startsWith(p.join(_workspace, 'archive')) &&
        p.basename(k).startsWith('checkpoint_'))
    .toList();

void main() {
  // ── Checkpoint writing ───────────────────────────────────────────────────

  group('save — checkpoint writing', () {
    test('writes exactly one checkpoint file', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(_checkpoints(io), hasLength(1));
    });

    test('checkpoint filename has checkpoint_ prefix', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(p.basename(_checkpoints(io).first), startsWith('checkpoint_'));
    });

    test('checkpoint filename contains sanitised branch name', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      // fix/null-ref → fix_null-ref
      expect(p.basename(_checkpoints(io).first), contains('fix_null-ref'));
    });

    test('checkpoint filename ends with .md', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(_checkpoints(io).first, endsWith('.md'));
    });

    test('checkpoint content contains handoff data and updated timestamp', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final content = io.read(_checkpoints(io).first);
      // Checkpoint is the stamped handoff — verify key content is present and
      // an Updated: timestamp was injected.
      expect(content, contains('# Agent Handoff — my-app'));
      expect(content, contains('ready-for-debug'));
      expect(content, contains('ConfigLoader splits path on spaces before resolving.'));
      expect(content, contains('> Updated: '));
    });

    test('multiple saves write multiple distinct checkpoints', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      // Small pause ensures distinct timestamp in filename.
      await Future<void>.delayed(const Duration(seconds: 1));
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(_checkpoints(io), hasLength(2));
    });

    test('writes checkpoint even when root cause not confirmed (audit trail)',
        () async {
      final io = _io(handoff: _unconfirmedHandoff);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(_checkpoints(io), hasLength(1));
    });
  });

  // ── Skills.md — confirmed root cause ─────────────────────────────────────

  group('save — skills.md with confirmed root cause', () {
    test('returns SkillsUpdateResult.written', () async {
      final io = _io();
      final result = await runSave(
          io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(result, equals(SkillsUpdateResult.written));
    });

    test('creates skills.md when missing', () async {
      final io = _io();
      expect(io.fileExists(skillsPathFor(_workspace)), isFalse);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(io.fileExists(skillsPathFor(_workspace)), isTrue);
    });

    test('pending entry contains branch name', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      // Branch name in skills entries is the real branch — not sanitized.
      expect(skills, contains('fix/null-ref'));
    });

    test('pending entry contains root cause text', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('ConfigLoader splits path on spaces'));
    });

    test('pending entry contains hot files when changed files are named',
        () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('loader.dart'));
    });

    test('root cause entry without changed files writes only one pending entry',
        () async {
      final io = _io(handoff: _confirmedNoFilesHandoff);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      // Only one pending entry (root cause). No hot files entry.
      final pendingEntries =
          RegExp(r'^- `', multiLine: true).allMatches(skills).length;
      expect(pendingEntries, equals(1));
    });

    test('appends to existing skills.md without clobbering', () async {
      final io = _io();
      io.write(
        skillsPathFor(_workspace),
        '# Accumulated Skills\n\n## Hot Paths\n\nexisting entry\n',
      );
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('existing entry'));
      expect(skills, contains('ConfigLoader'));
    });

    test('multiple saves accumulate distinct entries in Pending section',
        () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      // Two root cause entries (one per save).
      final pendingRootCauses =
          'ConfigLoader splits path on spaces'.allMatches(skills).length;
      expect(pendingRootCauses, equals(2));
    });

    test('Pending section header appears exactly once', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final skills = io.read(skillsPathFor(_workspace));
      expect('## Pending'.allMatches(skills).length, equals(1));
    });
  });

  // ── Skills.md — root cause not confirmed ─────────────────────────────────

  group('save — skills.md with unconfirmed root cause', () {
    test('returns SkillsUpdateResult.skipped', () async {
      final io = _io(handoff: _unconfirmedHandoff);
      final result = await runSave(
          io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(result, equals(SkillsUpdateResult.skipped));
    });

    test('does not create skills.md when root cause unconfirmed', () async {
      final io = _io(handoff: _unconfirmedHandoff);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(io.fileExists(skillsPathFor(_workspace)), isFalse);
    });

    test('does not touch existing skills.md when root cause unconfirmed',
        () async {
      final io = _io(handoff: _unconfirmedHandoff);
      const existing = '# Accumulated Skills\n\n## Hot Paths\n\nsome entry\n';
      io.write(skillsPathFor(_workspace), existing);
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      expect(io.read(skillsPathFor(_workspace)), equals(existing));
    });
  });

  // ── Registry ──────────────────────────────────────────────────────────────

  group('save — registry', () {
    test('touches lastSession in registry', () async {
      final io = _io();
      await runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit);
      final entry = Registry.load(io: io).findByName('my-app')!;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect(entry.lastSession, equals(today));
    });
  });

  // ── Error cases ───────────────────────────────────────────────────────────

  group('save — error cases', () {
    test('exits when project not in registry', () async {
      final io = MemoryFileIO();
      Registry.empty().save(io: io); // empty registry

      await expectLater(
        runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit),
        throwsA(isA<_ExitException>()),
      );
    });

    test('exits when handoff file missing', () async {
      const entry = RegistryEntry(
        name: 'my-app',
        projectRoot: _projectRoot,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      );
      final io = MemoryFileIO(); // no handoff file
      Registry.empty().add(entry).save(io: io);

      await expectLater(
        runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit),
        throwsA(isA<_ExitException>()),
      );
      // No checkpoint written.
      expect(_checkpoints(io), isEmpty);
    });

    test('no skills.md written on error path', () async {
      final io = MemoryFileIO();
      Registry.empty().save(io: io);

      await expectLater(
        runSave(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit),
        throwsA(isA<_ExitException>()),
      );
      expect(io.fileExists(skillsPathFor(_workspace)), isFalse);
    });
  });
}
