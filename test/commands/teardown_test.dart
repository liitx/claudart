import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/teardown.dart' show runTeardown, TeardownCategory;
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';

// Handoff with root cause and changed files populated — exercises pre-population.
const _richHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-01 | Branch: fix/null-ref

---

## Status

debug-in-progress

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
lib/config/loader.dart

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

// Handoff with no context filled in — no pre-population defaults available.
const _bareHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-01 | Branch: feat/parser

---

## Status

suggest-investigating

---

## Bug

Parser returns empty on malformed input.

---

## Expected Behavior

Parser returns null or throws on malformed input.

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

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

/// Builds a [MemoryFileIO] pre-seeded with a registry entry and optional handoff.
MemoryFileIO _io({String? handoff}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-01',
  );
  final io = MemoryFileIO(
    files: {
      if (handoff != null) handoffPathFor(_workspace): handoff,
    },
  );
  Registry.empty().add(entry).save(io: io);
  return io;
}

/// Returns all archive files (not checkpoints) written under the workspace.
List<String> _archives(MemoryFileIO io) => io.files.keys
    .where((k) =>
        k.startsWith(p.join(_workspace, 'archive')) &&
        p.basename(k).startsWith('handoff_'))
    .toList();

/// Builds a prompt function that returns answers from [queue] in order.
/// Returns null (optional skip) once the queue is exhausted.
String? Function(String, {bool optional}) _prompts(List<String?> queue) {
  final iter = queue.iterator;
  return (String _, {bool optional = false}) {
    if (!iter.moveNext()) return null;
    return iter.current;
  };
}

/// Builds a pickFn that always selects [cat] from the category menu.
int Function(List<String>) _pick(TeardownCategory cat) => (_) => cat.index;

// Category selection uses TeardownCategory constants (mirrors menu indices).

/// Full set of answers for a successful teardown against [_richHandoff].
/// Prompt order: fixSummary, hotFiles, coldFiles, pattern, fixPattern.
/// Category is supplied via pickFn (index 5 = state-management).
List<String?> get _richAnswers => [
      'Quoted path before passing to ConfigLoader.',  // fixSummary
      null,    // hotFiles — accept pre-populated default
      null,    // coldFiles — skip (optional)
      null,    // pattern — accept pre-populated default
      'Always quote paths that may contain spaces.',  // fixPattern
    ];

/// Full set of answers for a successful teardown against [_bareHandoff].
/// Category supplied via pickFn (index 5 = provider-state).
List<String?> get _bareAnswers => [
      'Added null guard before JSON decode.',        // fixSummary
      'lib/parser.dart',                            // hotFiles — no default, must enter
      null,                                         // coldFiles — skip
      'Parser crashes on malformed input.',         // pattern — no default, must enter
      'Always guard before decode with null check.',// fixPattern
    ];

void main() {
  // ── Early exit ────────────────────────────────────────────────────────────

  group('teardown — early exit', () {
    test('exits 0 with no active handoff (file missing)', () async {
      final io = _io(); // no handoff seeded
      await expectLater(
        runTeardown(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: _pick(TeardownCategory.general),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('exits 0 with blank handoff content', () async {
      final io = _io(handoff: '');
      await expectLater(
        runTeardown(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: _pick(TeardownCategory.general),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('exits 1 when project not in registry', () async {
      final io = MemoryFileIO();
      Registry.empty().save(io: io); // empty registry — no entry

      await expectLater(
        runTeardown(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts([]),
          pickFn: _pick(TeardownCategory.general),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });

  // ── User cancels ──────────────────────────────────────────────────────────

  group('teardown — user cancels', () {
    test('exits 0 when user declines "is the bug confirmed resolved?"',
        () async {
      final io = _io(handoff: _richHandoff);
      await expectLater(
        runTeardown(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false, // decline
          promptFn: _prompts([]),
          pickFn: _pick(TeardownCategory.general),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );
    });

    test('handoff is untouched when user cancels', () async {
      final io = _io(handoff: _richHandoff);
      try {
        await runTeardown(
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts([]),
          pickFn: _pick(TeardownCategory.general),
          exitFn: _throwExit,
        );
      } on _ExitException {
        // expected
      }
      expect(io.read(handoffPathFor(_workspace)), equals(_richHandoff));
    });
  });

  // ── Successful teardown ───────────────────────────────────────────────────

  group('teardown — archive and reset', () {
    test('writes one archive file', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      expect(_archives(io), hasLength(1));
    });

    test('archive filename contains sanitised branch name', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      expect(p.basename(_archives(io).first), contains('fix_null-ref'));
    });

    test('archive content matches original handoff', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final archived = io.read(_archives(io).first);
      expect(archived, contains('Config not loaded when path has spaces'));
    });

    test('handoff is reset to blank after teardown', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, isNot(contains('Config not loaded when path has spaces')));
    });
  });

  // ── Skills.md ─────────────────────────────────────────────────────────────

  group('teardown — skills.md', () {
    test('creates skills.md when it does not exist', () async {
      final io = _io(handoff: _richHandoff);
      expect(io.fileExists(skillsPathFor(_workspace)), isFalse);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      expect(io.fileExists(skillsPathFor(_workspace)), isTrue);
    });

    test('appends root cause pattern entry', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('state-management'));
      // pre-populated pattern accepted from root cause
      expect(skills, contains('ConfigLoader splits path on spaces'));
    });

    test('appends hot path entry for changed file', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('loader.dart'));
    });

    test('appends session index entry', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('resolved'));
      expect(skills, contains('fix/null-ref'));
    });

    test('appends cold file anti-pattern entry when provided', () async {
      final io = _io(handoff: _richHandoff);
      final answers = [
        'Fixed it.',                     // fixSummary
        null,                            // hotFiles default
        'lib/config/validator.dart',     // coldFiles — explore but not the cause
        null,                            // pattern default
        'Validate path before loading.', // fixPattern
      ];
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(answers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('validator.dart'));
      expect(skills, contains('Anti-patterns'));
    });

    test('does not write duplicate section headers on repeated teardowns',
        () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      // Plant a new session and run teardown again.
      io.write(handoffPathFor(_workspace), _bareHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_bareAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect('## Root Cause Patterns'.allMatches(skills).length, equals(1));
      expect('## Session Index'.allMatches(skills).length, equals(1));
    });
  });

  // ── Pre-population ────────────────────────────────────────────────────────

  group('teardown — pre-population', () {
    test('accepts pre-populated hotFiles when user returns null', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers), // hotFiles answer is null → use default
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // Default comes from "What changed" section: lib/config/loader.dart
      expect(skills, contains('loader.dart'));
    });

    test('uses override when user types a different hotFiles value', () async {
      final io = _io(handoff: _richHandoff);
      final answers = [
        'Fixed it.',
        'lib/config/resolver.dart',  // override hotFiles
        null,
        null,                        // accept pattern default
        'Always resolve before load.',
      ];
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(answers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('resolver.dart'));
    });

    test('accepts pre-populated pattern when user returns null', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers), // pattern answer is null → use root cause
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('ConfigLoader splits path on spaces'));
    });

    test('uses override when user types a different pattern', () async {
      final io = _io(handoff: _richHandoff);
      final answers = [
        'Fixed it.',
        null,
        null,
        'Custom pattern override.',  // override pattern
        'Re-attach listener.',
      ];
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(answers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('Custom pattern override.'));
      expect(skills, isNot(contains('ConfigLoader splits path on spaces')));
    });

    test('no hotFiles default when changedFiles is blank', () async {
      // _bareHandoff has _Nothing yet._ in changed files.
      // hotFiles prompt gets no default so user must provide one explicitly.
      final io = _io(handoff: _bareHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_bareAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // User-entered value used.
      expect(skills, contains('parser.dart'));
    });

    test('no pattern default when root cause is blank', () async {
      final io = _io(handoff: _bareHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_bareAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // User-entered pattern used.
      expect(skills, contains('Parser crashes on malformed input.'));
    });
  });
}
