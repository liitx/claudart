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

> Session started: 2026-03-01 | Branch: fix/audio-stop

---

## Status

debug-in-progress

---

## Bug

Audio stops after source switch.

---

## Expected Behavior

Audio continues seamlessly.

---

## Root Cause

StateNotifier holds stale reference after hot-reload.

---

## Scope

### Files in play
lib/audio/audio_bloc.dart

### BLoCs / providers in play
AudioBloc

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
Traced event through BLoC.

### What changed (files modified)
lib/audio/audio_bloc.dart

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

> Session started: 2026-03-01 | Branch: fix/bare

---

## Status

suggest-investigating

---

## Bug

Something broken.

---

## Expected Behavior

Should work.

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### BLoCs / providers in play
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
  final entry = RegistryEntry(
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

/// Builds a pickFn that always selects [index] from the category menu.
int Function(List<String>) _pick(int index) => (_) => index;

// Category selection uses TeardownCategory constants (mirrors menu indices).

/// Full set of answers for a successful teardown against [_richHandoff].
/// Prompt order: fixSummary, hotFiles, coldFiles, pattern, fixPattern.
/// Category is supplied via pickFn (index 1 = bloc-event-handling).
List<String?> get _richAnswers => [
      'Replaced stale reference with fresh copy on each event.',  // fixSummary
      null,    // hotFiles — accept pre-populated default
      null,    // coldFiles — skip (optional)
      null,    // pattern — accept pre-populated default
      'Replace stale StateNotifier reference in BLoC constructor.',// fixPattern
    ];

/// Full set of answers for a successful teardown against [_bareHandoff].
/// Category supplied via pickFn (index 5 = provider-state).
List<String?> get _bareAnswers => [
      'Fixed the issue by adding a null check.',   // fixSummary
      'lib/provider/my_provider.dart',             // hotFiles — no default, must enter
      null,                                        // coldFiles — skip
      'Provider holds stale state after reload.',  // pattern — no default, must enter
      'Re-initialise provider on lifecycle resume.',// fixPattern
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      expect(p.basename(_archives(io).first), contains('fix_audio-stop'));
    });

    test('archive content matches original handoff', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final archived = io.read(_archives(io).first);
      expect(archived, contains('Audio stops after source switch'));
    });

    test('handoff is reset to blank after teardown', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, isNot(contains('Audio stops after source switch')));
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('bloc-event-handling'));
      // pre-populated pattern accepted from root cause
      expect(skills, contains('StateNotifier holds stale reference'));
    });

    test('appends hot path entry for changed file', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('audio_bloc.dart'));
    });

    test('appends session index entry', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('resolved'));
      expect(skills, contains('fix/audio-stop'));
    });

    test('appends cold file anti-pattern entry when provided', () async {
      final io = _io(handoff: _richHandoff);
      final answers = [
        'Fixed it.',               // fixSummary
        null,                      // hotFiles default
        'lib/audio/player.dart',   // coldFiles — explore but not the cause
        null,                      // pattern default
        'Re-attach listener.',     // fixPattern
      ];
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(answers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('player.dart'));
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      // Plant a new session and run teardown again.
      io.write(handoffPathFor(_workspace), _bareHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_bareAnswers),
        pickFn: _pick(TeardownCategory.providerState),
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // Default comes from "What changed" section: lib/audio/audio_bloc.dart
      expect(skills, contains('audio_bloc.dart'));
    });

    test('uses override when user types a different hotFiles value', () async {
      final io = _io(handoff: _richHandoff);
      final answers = [
        'Fixed it.',
        'lib/audio/stream_handler.dart', // override hotFiles
        null,
        null,                            // accept pattern default
        'Re-attach listener.',
      ];
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(answers),
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('stream_handler.dart'));
    });

    test('accepts pre-populated pattern when user returns null', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers), // pattern answer is null → use root cause
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('StateNotifier holds stale reference'));
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
        pickFn: _pick(TeardownCategory.blocEventHandling),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('Custom pattern override.'));
      expect(skills, isNot(contains('StateNotifier holds stale reference')));
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
        pickFn: _pick(TeardownCategory.providerState),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // User-entered value used.
      expect(skills, contains('my_provider.dart'));
    });

    test('no pattern default when root cause is blank', () async {
      final io = _io(handoff: _bareHandoff);
      await runTeardown(
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_bareAnswers),
        pickFn: _pick(TeardownCategory.providerState),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      // User-entered pattern used.
      expect(skills, contains('Provider holds stale state after reload.'));
    });
  });
}
