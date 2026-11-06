import 'dart:async';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/support/claudart_command.dart';
import 'package:claudart/commands/teardown.dart'
    show kTeardownSkipDebugQuestion, runTeardown, TeardownCategory;
import 'package:claudart/session/debug_disposition.dart';
import 'package:claudart/session/md_io.dart'
    show readHandoffStatus, readSection, updateSection, withDebugDisposition;
import 'package:claudart/config/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/templates/handoff_template.dart' show blankHandoff;
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/io/file_io.dart';
import 'package:claudart/session/workspace_guard.dart';
import '../helpers/logged_moves.dart';
import '../helpers/fake_executors.dart';
import '../helpers/mocks.dart';
import '../helpers/unscripted.dart';
import '../helpers/project_fixture.dart';

const _projectRoot = ProjectFixture.root;
const _workspace = ProjectFixture.workspace;

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
/// Matches the injectable `pickFn` signature on teardown (the menu gained an
/// optional `startIndex` for preselection); the stub ignores it.
int Function(List<String>, {int startIndex}) _pick(TeardownCategory cat) =>
    (_, {int startIndex = 0}) => cat.index;

/// Like [_pick], but answers the 2-item "archive / reminder" menu with
/// [kind] (0 = archive, 1 = reminder) instead of always falling through to
/// the category index — [_pick] can't reach the reminder branch because it
/// answers every menu with the same category index.
int Function(List<String>, {int startIndex}) _pickKind(
  TeardownCategory cat, {
  required int kind,
}) =>
    (items, {int startIndex = 0}) => items.length == 2 ? kind : cat.index;

/// Delegates all ops to [delegate] but throws on write to [failPath].
class _FailOnWriteIO implements FileIO {
  final MemoryFileIO delegate;
  final String failPath;
  _FailOnWriteIO({required this.delegate, required this.failPath});

  @override
  void write(String path, String content) {
    if (path == failPath) throw Exception('simulated write failure');
    delegate.write(path, content);
  }

  @override void append(String path, String content) =>
      delegate.append(path, content);
  @override T withExclusiveLock<T>(String path, T Function() body) =>
      delegate.withExclusiveLock(path, body);
  @override String read(String path) => delegate.read(path);
  @override void delete(String path) => delegate.delete(path);
  @override bool fileExists(String path) => delegate.fileExists(path);
  @override bool dirExists(String path) => delegate.dirExists(path);
  @override void createDir(String path) => delegate.createDir(path);
  @override List<String> listFiles(String d, {String? extension}) =>
      delegate.listFiles(d, extension: extension);
  @override bool linkExists(String path) => delegate.linkExists(path);
  @override void deleteLink(String path) => delegate.deleteLink(path);
  @override void createLink(String linkPath, String targetPath) =>
      delegate.createLink(linkPath, targetPath);
}

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
          executor: noModelExecutor(),
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
          executor: noModelExecutor(),
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
          executor: noModelExecutor(),
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

    test('prints which project it resolved before doing anything', () async {
      final io = _io(); // no handoff seeded
      final output = <String>[];
      await expectLater(
        runZoned(
          () => runTeardown(
            executor: noModelExecutor(),
            io: io,
            projectRootOverride: _projectRoot,
            confirmFn: (_) => true,
            promptFn: _prompts([]),
            pickFn: _pick(TeardownCategory.general),
            exitFn: _throwExit,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(output.join('\n'), contains('Project  : my-app'));
    });
  });

  // ── User cancels ──────────────────────────────────────────────────────────

  group('teardown — user cancels', () {
    test('exits 0 when user declines "is the bug confirmed resolved?"',
        () async {
      final io = _io(handoff: _richHandoff);
      await expectLater(
        runTeardown(
          executor: noModelExecutor(),
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
          executor: noModelExecutor(),
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

  group('teardown — transition log', () {
    Future<void> teardown(MemoryFileIO io, {int? kind}) => runTeardown(
      executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts(_richAnswers),
          pickFn: kind == null
              ? _pick(TeardownCategory.stateManagement)
              : _pickKind(TeardownCategory.stateManagement, kind: kind),
          exitFn: _throwExit,
        );

    test('a headless debugComplete teardown logs tornDown into noHandoff',
        () async {
      final io = _io(
        handoff: withDebugDisposition(
          _richHandoff.replaceFirst('debug-in-progress', 'debug-complete'),
          DebugDisposition.verified,
        ),
      );
      await runTeardown(
        executor: noModelExecutor(),
        confirmFn: unscriptedConfirm,
        
        io: io,
        projectRootOverride: _projectRoot,
        mode: RunMode.headless,
        exitFn: _throwExit,
      );
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.teardown.name,
          'from': HandoffStatus.debugComplete.name,
          'event': HandoffEvent.tornDown.name,
          'to': HandoffStatus.noHandoff.name,
        },
      ]);
    });

    test('confirming resolved and recording debug as skipped, from '
        'debugInProgress, logs tornDown as a legal move', () async {
      final io = _io(handoff: _richHandoff); // status: debug-in-progress
      await teardown(io);
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.teardown.name,
          'from': HandoffStatus.debugInProgress.name,
          'event': HandoffEvent.tornDown.name,
          'to': HandoffStatus.noHandoff.name,
        },
      ]);
    });

    test('the archived handoff records debug as skipped', () async {
      final io = _io(handoff: _richHandoff);
      await teardown(io);
      final archived = io.files.entries
          .where((e) => e.key.startsWith(p.join(_workspace, 'archive')) &&
              e.key.endsWith('.md') &&
              !e.key.contains('index'))
          .map((e) => e.value)
          .join('\n');
      expect(
        archived,
        contains('## Debug Disposition\n\n${DebugDisposition.skipped.wire}'),
      );
    });

    group('the question about debug', () {
      /// Runs teardown, answering each confirmation by [answers] in order (then
      /// yes), and returns the questions that were asked.
      Future<List<String>> questionsFor(
        String handoff,
        List<bool> answers,
      ) async {
        final io = _io(handoff: handoff);
        final asked = <String>[];
        final queue = [...answers];
        await runTeardown(
          executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (question) {
            asked.add(question);
            return queue.isEmpty ? true : queue.removeAt(0);
          },
          promptFn: _prompts(_richAnswers),
          pickFn: _pick(TeardownCategory.stateManagement),
          exitFn: _throwExit,
        ).catchError((Object _) {});
        return asked;
      }

      test('is asked when debug did not run for a complete transfer', () async {
        final asked = await questionsFor(_richHandoff, [true]);
        expect(asked, contains(kTeardownSkipDebugQuestion));
      });

      test('is not asked after a finished fix', () async {
        final asked = await questionsFor(
          _richHandoff.replaceFirst('debug-in-progress', 'debug-complete'),
          [true],
        );
        expect(asked, isNot(contains(kTeardownSkipDebugQuestion)));
      });

      test('is not asked while the transfer is incomplete', () async {
        final asked = await questionsFor(
          _richHandoff
              .replaceFirst('debug-in-progress', 'suggest-investigating')
              .replaceFirst(
                'ConfigLoader splits path on spaces before resolving.',
                '_Not yet determined._',
              ),
          [true],
        );
        expect(asked, isNot(contains(kTeardownSkipDebugQuestion)));
      });

      test('declining it is not resolved: nothing is torn down and the '
          'session stays live', () async {
        final io = _io(handoff: _richHandoff);
        // resolved? yes, record as skipped? no, save as a reminder? yes
        final answers = [true, false, true];
        await runTeardown(
          executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => answers.removeAt(0),
          promptFn: _prompts(['still pending']),
          pickFn: _pick(TeardownCategory.stateManagement),
          exitFn: _throwExit,
        ).catchError((Object _) {});
        expect(loggedMoves(io, _workspace), isEmpty);
        expect(
          readHandoffStatus(io.read(handoffPathFor(_workspace))),
          HandoffStatus.debugInProgress,
        );
      });
    });

    test('saving a reminder logs reminderSaved into noHandoff', () async {
      final io = _io(handoff: _richHandoff);
      await teardown(io, kind: 1);
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.teardown.name,
          'from': HandoffStatus.debugInProgress.name,
          'event': HandoffEvent.reminderSaved.name,
          'to': HandoffStatus.noHandoff.name,
        },
      ]);
    });

    test('declining "is the bug resolved?" resets nothing and logs nothing',
        () async {
      final io = _io(handoff: _richHandoff);
      await expectLater(
        runTeardown(
          executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => false,
          promptFn: _prompts(_richAnswers),
          pickFn: _pick(TeardownCategory.stateManagement),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>()),
      );
      expect(loggedMoves(io, _workspace), isEmpty);
    });
  });

  group('teardown — archive and reset', () {
    test('writes one archive file', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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

  group('teardown — Pending entry removal', () {
    test('removes the resolved branch\'s Pending entry on archive', () async {
      final io = _io(handoff: _richHandoff);
      io.write(skillsPathFor(_workspace), '''## Pending

- `fix/null-ref` (2026-03-01): root cause — a prior /save guess

## Root Cause Patterns

_None recorded yet._
''');
      await runTeardown(
        executor: noModelExecutor(),
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pick(TeardownCategory.stateManagement),
        exitFn: _throwExit,
      );
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, isNot(contains('a prior /save guess')));
    });
  });

  group('teardown — skills.md', () {
    test('creates skills.md when it does not exist', () async {
      final io = _io(handoff: _richHandoff);
      expect(io.fileExists(skillsPathFor(_workspace)), isFalse);
      await runTeardown(
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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
        executor: noModelExecutor(),
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

  // ── Headless mode ────────────────────────────────────────────────────────────

  // A headless teardown archives, and updates what was learned, only when the
  // handoff's evidence is verified (Q11, owner agreed): a fix that was applied
  // and analyzed but never verified, and a handoff only suggest confirmed, are
  // saved as reminders.
  group('teardown — headless closes only on verified evidence', () {
    const cases = <({
      String name,
      String status,
      DebugDisposition? disposition,
      bool archives,
    })>[
      (
        name: 'a verified fix',
        status: 'debug-complete',
        disposition: DebugDisposition.verified,
        archives: true,
      ),
      (
        name: 'a fix applied and analyzed, never verified',
        status: 'debug-complete',
        disposition: DebugDisposition.done,
        archives: false,
      ),
      (
        name: 'a finished fix with no disposition recorded',
        status: 'debug-complete',
        disposition: null,
        archives: false,
      ),
      (
        name: 'a handoff suggest confirmed, debug skipped',
        status: 'ready-for-debug',
        disposition: DebugDisposition.skipped,
        archives: false,
      ),
    ];

    for (final scenario in cases) {
      test('${scenario.name}: '
          '${scenario.archives ? 'archives and resets' : 'saves a reminder'}',
          () async {
        var handoff =
            _richHandoff.replaceFirst('debug-in-progress', scenario.status);
        if (scenario.disposition != null) {
          handoff = withDebugDisposition(handoff, scenario.disposition!);
        }
        final io = _io(handoff: handoff);
        try {
          await runTeardown(
            executor: noModelExecutor(),
            io: io,
            projectRootOverride: _projectRoot,
            mode: RunMode.headless,
            exitFn: _throwExit,
          );
        } on _ExitException {
          // The reminder path leaves through exit 0.
        }
        final events = [
          for (final move in loggedMoves(io, _workspace)) move['event'],
        ];
        // A reminder leaves the handoff where it is and logs no move (gap
        // R16): only the resolved path records one.
        expect(events, scenario.archives ? [HandoffEvent.tornDown.name] : isEmpty);
        expect(io.read(handoffPathFor(_workspace)) == blankHandoff,
            scenario.archives);
        if (!scenario.archives) {
          expect(io.read(handoffPathFor(_workspace)), handoff,
              reason: 'a reminder leaves the handoff untouched');
        }
        expect(_archives(io), hasLength(1));
        expect(io.read(skillsPathFor(_workspace)).contains('resolved'),
            scenario.archives);
      });
    }
  });

  group('teardown — headless', () {
    Never Function(String) throwOnCall(String label) =>
        (_) => throw StateError('headless must never call $label');

    test('a verified debugComplete archives without asking anything — every '
        'human touchpoint would throw if called', () async {
      final completeHandoff = withDebugDisposition(
        _richHandoff.replaceFirst('debug-in-progress', 'debug-complete'),
        DebugDisposition.verified,
      );
      final io = _io(handoff: completeHandoff);

      await runTeardown(
        executor: noModelExecutor(),
        io: io,
        projectRootOverride: _projectRoot,
        mode: RunMode.headless,
        confirmFn: (q) => throw StateError('headless must never call confirmFn: $q'),
        promptFn: (q, {optional = false}) =>
            throw StateError('headless must never call promptFn: $q'),
        pickFn: (items, {startIndex = 0}) =>
            throw StateError('headless must never call pickFn'),
        exitFn: _throwExit,
      );

      expect(io.read(handoffPathFor(_workspace)), equals(blankHandoff),
          reason: 'resolved path resets the handoff, same as interactive');
      expect(_archives(io), hasLength(1));
      final skills = io.read(skillsPathFor(_workspace));
      expect(skills, contains('resolved'),
          reason: 'resolved sessions promote to skills.md same as interactive');
    });

    test('non-debugComplete status saves a reminder instead of archiving, '
        'handoff left untouched', () async {
      final io = _io(handoff: _richHandoff); // status: debug-in-progress

      await expectLater(
        runTeardown(
          executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          mode: RunMode.headless,
          confirmFn: throwOnCall('confirmFn'),
          promptFn: (q, {optional = false}) =>
              throw StateError('headless must never call promptFn: $q'),
          pickFn: (items, {startIndex = 0}) =>
              throw StateError('headless must never call pickFn'),
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );

      expect(io.read(handoffPathFor(_workspace)), equals(_richHandoff),
          reason: 'unresolved path never resets the handoff — same as a '
              'human declining the interactive confirm');
      expect(_archives(io), hasLength(1),
          reason: 'a reminder is still archived — headless never silently '
              'discards an unresolved session\'s context');
    });

    test('prints a Headless decision summary before writing the reminder '
        'archive entry — the reminder write happens with no human prompt '
        'too, same as the resolved path\'s fuller summary', () async {
      final io = _io(handoff: _richHandoff); // status: debug-in-progress
      final output = <String>[];

      await expectLater(
        runZoned(
          () => runTeardown(
            executor: noModelExecutor(),
            io: io,
            projectRootOverride: _projectRoot,
            mode: RunMode.headless,
            confirmFn: throwOnCall('confirmFn'),
            promptFn: (q, {optional = false}) =>
                throw StateError('headless must never call promptFn: $q'),
            pickFn: (items, {startIndex = 0}) =>
                throw StateError('headless must never call pickFn'),
            exitFn: _throwExit,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 0)),
      );

      final printed = output.join('\n');
      expect(printed, contains('Headless decision'));
      expect(printed, contains('Record type : reminder'));
    });

    test('never records the unspecified sentinel as a real hot-path file '
        'when no hot files are known', () async {
      // Converged (a real root cause and scope) and verified, but with no
      // changed files recorded, so no hot files are known.
      final completeHandoff = withDebugDisposition(
        updateSection(
          updateSection(
            _bareHandoff.replaceFirst('suggest-investigating', 'debug-complete'),
            'Root Cause',
            'The splitter stops early.',
          ),
          'Scope',
          '### Files in play\n- lib/parser.dart',
        ),
        DebugDisposition.verified,
      );
      final io = _io(handoff: completeHandoff);

      await runTeardown(
        executor: noModelExecutor(),
        io: io,
        projectRootOverride: _projectRoot,
        mode: RunMode.headless,
        confirmFn: throwOnCall('confirmFn'),
        promptFn: (q, {optional = false}) =>
            throw StateError('headless must never call promptFn: $q'),
        pickFn: (items, {startIndex = 0}) =>
            throw StateError('headless must never call pickFn'),
        exitFn: _throwExit,
      );

      final skills = io.read(skillsPathFor(_workspace));
      final hotPaths = readSection(skills, 'Hot Paths');
      expect(hotPaths, isNot(contains('unspecified')),
          reason: '"unspecified" is display-only text for the headless '
              'summary — it must never be written into skills.md\'s Hot '
              'Paths section as if it were a real hot-path file');
    });
  });

  group('teardown — reminder kind', () {
    test('does not update skills.md ("no skills update" per ArchiveKind.reminder)', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        executor: noModelExecutor(),
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pickKind(TeardownCategory.stateManagement, kind: 1),
        exitFn: _throwExit,
      );
      expect(io.files.containsKey(skillsPathFor(_workspace)), isFalse);
    });

    test('still archives the handoff', () async {
      final io = _io(handoff: _richHandoff);
      await runTeardown(
        executor: noModelExecutor(),
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        promptFn: _prompts(_richAnswers),
        pickFn: _pickKind(TeardownCategory.stateManagement, kind: 1),
        exitFn: _throwExit,
      );
      expect(_archives(io), hasLength(1));
    });
  });

  group('teardown — guarded mutation', () {
    test('a failed write leaves the workspace lock as an interrupted-state signal', () async {
      final base = _io(handoff: _richHandoff);
      final io = _FailOnWriteIO(delegate: base, failPath: skillsPathFor(_workspace));

      Object? caught;
      try {
        await runTeardown(
          executor: noModelExecutor(),
          io: io,
          projectRootOverride: _projectRoot,
          confirmFn: (_) => true,
          promptFn: _prompts(_richAnswers),
          pickFn: _pickKind(TeardownCategory.stateManagement, kind: 0),
          exitFn: _throwExit,
        );
      } on Exception catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(isLocked(_workspace, io: base), isTrue);
    });
  });
}
