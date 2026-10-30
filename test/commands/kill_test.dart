import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/support/claudart_command.dart';
import 'package:claudart/commands/kill.dart';
import 'package:claudart/io/file_io.dart';
import 'package:claudart/io/git_utils.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/config/paths.dart';
import 'package:claudart/templates/handoff_template.dart' show blankHandoff;
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/session/workspace_guard.dart';
import 'package:claudart/workspace/workspace_index.dart';
import '../helpers/logged_moves.dart';
import '../helpers/mocks.dart';
import '../helpers/project_fixture.dart';
import 'package:claudart/commands/support/command_seams.dart';

const _projectRoot = ProjectFixture.root;
const _workspace = ProjectFixture.workspace;
const _claudeLink = '/projects/my-app/.claude';

const _activeHandoff = '''# Agent Handoff — my-app

> Session started: 2026-03-16 | Branch: feat/fix

---

## Status

ready-for-debug

---

## Bug

Something is broken.

---

## Expected Behavior

It should work.

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

/// Builds a registry pre-seeded with one entry for _projectRoot → _workspace.
MemoryFileIO _io({
  bool withHandoff = true,
  bool withLink = true,
  bool withRealDir = false,
}) {
  const entry = RegistryEntry(
    name: 'my-app',
    projectRoot: _projectRoot,
    workspacePath: _workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-03-15',
  );
  final registry = Registry.empty().add(entry);
  final io = MemoryFileIO(
    files: {
      if (withHandoff) handoffPathFor(_workspace): _activeHandoff,
    },
    links: {if (withLink) _claudeLink},
    dirs: {if (withRealDir) _claudeLink},
  );
  // Write registry so Registry.load() finds it.
  registry.save(io: io);
  return io;
}

void main() {
  group('kill — transition log', () {
    test('logs killed from the status the handoff was in', () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.kill.name,
          'from': HandoffStatus.readyForDebug.name,
          'event': HandoffEvent.killed.name,
          'to': HandoffStatus.noHandoff.name,
        },
      ]);
    });

    test('logs nothing when the user declines', () async {
      final io = _io();
      await expectLater(
        runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => false, exitFn: (code) => throw _ExitException(code))),
        throwsA(isA<_ExitException>()),
      );
      expect(loggedMoves(io, _workspace), isEmpty);
    });

    test('a blank handoff is logged as a move the table lacks', () async {
      final io = _io(withHandoff: false);
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      expect(loggedMoves(io, _workspace), [
        {
          'command': ClaudartCommand.kill.name,
          'from': HandoffStatus.unknown.name,
          'event': HandoffEvent.killed.name,
          'rejected': true,
        },
      ]);
    });
  });

  group('kill — session summary', () {
    test('a blank handoff is shown as no-handoff, not its stale Status line',
        () async {
      final io = _io();
      io.write(handoffPathFor(_workspace), blankHandoff);
      final output = <String>[];
      await runZoned(
        () => runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(output.join('\n'), contains('Status : no-handoff'));
    });

    Future<String> summaryFor(String handoff) async {
      final io = _io();
      io.write(handoffPathFor(_workspace), handoff);
      final output = <String>[];
      await runZoned(
        () => runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      return output.join('\n');
    }

    test('recorded attempted and changed work is shown', () async {
      final summary = await summaryFor(
        _activeHandoff
            .replaceFirst(
              '### What was attempted\n_Nothing yet._',
              '### What was attempted\nTried the first fix',
            )
            .replaceFirst(
              '### What changed (files modified)\n_Nothing yet._',
              '### What changed (files modified)\nlib/a.dart',
            ),
      );
      expect(summary, contains('Attempted : Tried the first fix'));
      expect(summary, contains('Changed   : lib/a.dart'));
    });

    test('placeholder progress is not shown as work', () async {
      final summary = await summaryFor(_activeHandoff);
      expect(summary, isNot(contains('Attempted :')));
      expect(summary, isNot(contains('Changed   :')));
    });

    test('a live handoff shows its own status', () async {
      final io = _io();
      final output = <String>[];
      await runZoned(
        () => runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(output.join('\n'), contains('Status : ready-for-debug'));
    });
  });

  group('kill — the outcome is recorded', () {
    List<String> outcomesIn(MemoryFileIO io, String logsDir) => [
          for (final line in io
              .read(logFilePath(logsDir, LogFile.interactions))
              .split('\n')
              .where((l) => l.isNotEmpty))
            (jsonDecode(line)
                as Map<String, dynamic>)[LogEntryField.outcome.name] as String,
        ];

    Future<List<String>> outcomeOf(
      MemoryFileIO io, {
      bool confirm = true,
    }) async {
      await runZoned(
        () async {
          try {
            await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => confirm, exitFn: (code) => throw _ExitException(code)));
          } on _ExitException {
            // A refused kill ends with an exit; the log is the point.
          }
        },
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
      );
      return outcomesIn(io, logsDirFor(_workspace));
    }

    test('a kill from a status with nothing to lose is killed', () async {
      expect(await outcomeOf(_io()), [KillOutcome.killed.name]);
    });

    test('a kill from debugComplete is killedWithWarning', () async {
      final io = _io();
      io.write(
        handoffPathFor(_workspace),
        _activeHandoff.replaceFirst('ready-for-debug', 'debug-complete'),
      );
      expect(await outcomeOf(io), [KillOutcome.killedWithWarning.name]);
    });

    test('the warning is printed for debugComplete and for nothing else',
        () async {
      for (final entry in {
        'debug-complete': isTrue,
        'ready-for-debug': isFalse,
      }.entries) {
        final io = _io();
        io.write(
          handoffPathFor(_workspace),
          _activeHandoff.replaceFirst('ready-for-debug', entry.key),
        );
        final output = <String>[];
        await runZoned(
          () => runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => output.add(line),
          ),
        );
        expect(
          output.join('\n').contains(HandoffStatus.debugComplete.killWarning!),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('a declined kill is cancelled', () async {
      expect(
        await outcomeOf(_io(), confirm: false),
        [KillOutcome.cancelled.name],
      );
    });
  });

  group('kill — success path', () {
    test('archives handoff', () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      final archived = io.files.keys
          .where((k) => k.startsWith(p.join(_workspace, 'archive')) && k.endsWith('.md'))
          .toList();
      expect(archived, hasLength(1));
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      await runZoned(
        () => runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(output.join('\n'), contains('Project  : my-app'));
    });

    test('archived session is visible to `claudart archives` (index entry appended)', () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      final entries = loadIndex(_workspace, io: io);
      expect(entries, hasLength(1));
      expect(entries.first.branch, equals('feat/fix'));
    });

    test('resets handoff to blank', () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, isNot(contains('Something is broken')));
    });

    test('leaves the .claude symlink in place — kill closes a session, '
        'it does not deregister the project; unlink removes the link',
        () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      expect(io.linkExists(_claudeLink), isTrue);
    });

    test('updates registry lastSession', () async {
      final io = _io();
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      final registry = Registry.load(io: io);
      final entry = registry.findByName('my-app')!;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect(entry.lastSession, equals(today));
    });

    test('a real .claude/ directory (symlink was never possible) is not '
        'reported as "no active session"', () async {
      final io = _io(withLink: false, withRealDir: true);
      final confirmQuestions = <String>[];
      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (q) {
          confirmQuestions.add(q);
          return true;
        }, exitFn: (code) => throw _ExitException(code)));
      // "Kill anyway and archive the handoff?" is only asked when Step 4's
      // "no active session" branch is taken — it must not be, since a real
      // directory at .claude counts as an active session.
      expect(
        confirmQuestions,
        isNot(contains('Kill anyway and archive the handoff?')),
      );
      // Archive still happens — killing a real-directory workspace works
      // the same as killing a symlinked one.
      final archived = io.files.keys
          .where((k) => k.startsWith(p.join(_workspace, 'archive')))
          .where((k) => k.endsWith('.md'))
          .toList();
      expect(archived, hasLength(1));
    });
  });

  group('kill — rejected by user', () {
    test('leaves handoff intact when user declines', () async {
      final io = _io();
      await expectLater(
        runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => false, exitFn: (code) => throw _ExitException(code))) // decline on first confirmation
          ,
        throwsA(isA<_ExitException>()),
      );
      // Handoff should still contain the active content.
      final handoff = io.read(handoffPathFor(_workspace));
      expect(handoff, contains('Something is broken'));
    });
  });

  group('kill — locked workspace', () {
    test('leaves lock intact when user declines clear', () async {
      final io = _io();
      // Plant a lock file to simulate interrupted state.
      io.write(p.join(_workspace, 'workspace.lock'), 'setup');

      await expectLater(
        runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => false, exitFn: (code) => throw _ExitException(code))) // decline clear lock
          ,
        throwsA(isA<_ExitException>()),
      );

      // Workspace should still be locked.
      expect(isLocked(_workspace, io: io), isTrue);
    });

    test('proceeds after user confirms lock clear', () async {
      final io = _io();
      io.write(p.join(_workspace, 'workspace.lock'), 'setup');

      await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))) // accept all prompts including lock clear
        ;

      expect(isLocked(_workspace, io: io), isFalse);
    });
  });

  group('kill — branch display', () {
    test('prefers live git branch over stale handoff branch', () async {
      final realGit = detectGitContext();
      // Only meaningful inside a real git checkout — skip otherwise.
      if (realGit == null) return;

      final entry = RegistryEntry(
        name: 'my-app',
        projectRoot: realGit.root,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-03-15',
      );
      final io = MemoryFileIO(
        files: {handoffPathFor(_workspace): _activeHandoff},
        links: {_claudeLink},
      );
      Registry.empty().add(entry).save(io: io);

      final output = <String>[];
      await runZoned(
        () => runKill(seams: CommandSeams(io: io, projectRootOverride: null, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code))),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );

      final printed = output.join('\n');
      // _activeHandoff stores "Branch: feat/fix" — the live branch must win.
      expect(printed, contains('Branch : ${realGit.branch}'));
      expect(printed, isNot(contains('Branch : feat/fix')));
    });
  });

  group('kill — error handling', () {
    test('exits with code 1 when closeSession fails', () async {
      // Simulate a reset failure so closeSession throws SessionCloseException.
      // Rollback mechanics (handoff restored, archive deleted) are verified in
      // session_ops_test.dart. This test only verifies kill's error response.
      final io = _FailOnResetIO(delegate: _io());
      _ExitException? caught;
      try {
        await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      } on _ExitException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.code, equals(1));
    });

    test('clears the lock after a successful rollback — nothing is actually interrupted', () async {
      final io = _FailOnResetIO(delegate: _io());
      try {
        await runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, confirmFn: (_) => true, exitFn: (code) => throw _ExitException(code)));
      } on _ExitException catch (_) {}
      expect(isLocked(_workspace, io: io.delegate), isFalse);
    });
  });

  group('kill — consent is never inferred from missing input', () {
    Future<void> kill(MemoryFileIO io,
            {bool? Function(String)? askFn, bool Function(String)? confirmFn, RunMode mode = RunMode.interactive}) =>
        runKill(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, askFn: askFn, confirmFn: confirmFn, exitFn: (code) => throw _ExitException(code)), mode: mode);

    bool? neverAsked(String q) => throw StateError('should not have been asked: $q');
    Matcher exitsWith(int code) => throwsA(isA<_ExitException>().having((e) => e.code, 'code', code));
    // Snapshot files only: the archive writer also keeps an index.json there.
    List<String> archives(MemoryFileIO io) => io.files.keys
        .where((k) => k.startsWith(p.join(_workspace, 'archive')) && p.basename(k) != archiveIndexFileName)
        .toList();

    test('end of input at the final question stops with exit 1 and changes nothing', () async {
      final io = _io();
      await expectLater(kill(io, askFn: (_) => null), exitsWith(1));
      expect(io.read(handoffPathFor(_workspace)), contains('Something is broken'));
      expect(io.linkExists(_claudeLink), isTrue);
      expect(archives(io), isEmpty);
    });

    test('end of input at the lock question also stops with exit 1 and keeps the lock', () async {
      final io = _io();
      io.write(p.join(_workspace, 'workspace.lock'), 'setup');
      await expectLater(kill(io, askFn: (_) => null), exitsWith(1));
      expect(isLocked(_workspace, io: io), isTrue);
    });

    test('an explicit answer still decides (yes kills, no cancels with exit 0)', () async {
      final yes = _io();
      await kill(yes, askFn: (_) => true);
      expect(archives(yes), hasLength(1));
      await expectLater(kill(_io(), askFn: (_) => false), exitsWith(0));
    });

    group('--headless', () {
      test('kills without asking: archives, resets the handoff, keeps the link', () async {
        final io = _io();
        await kill(io, askFn: neverAsked, mode: RunMode.headless);
        expect(archives(io), hasLength(1));
        expect(io.read(handoffPathFor(_workspace)), isNot(contains('Something is broken')));
        expect(io.linkExists(_claudeLink), isTrue, reason: 'kill keeps the registration');
      });

      test('never prompts, even if an injected confirm would say no', () async {
        final io = _io();
        await kill(io, confirmFn: (_) => false, mode: RunMode.headless);
        expect(archives(io), hasLength(1));
      });

      test('never clears a workspace lock: exits 1 and leaves everything in place', () async {
        final io = _io();
        io.write(p.join(_workspace, 'workspace.lock'), 'setup');
        await expectLater(kill(io, askFn: neverAsked, mode: RunMode.headless), exitsWith(1));
        expect(isLocked(_workspace, io: io), isTrue);
        expect(io.read(handoffPathFor(_workspace)), contains('Something is broken'));
        expect(io.linkExists(_claudeLink), isTrue);
        expect(archives(io), isEmpty);
      });

      test('with no active session it still archives the handoff (benign, reversible)', () async {
        final io = _io(withLink: false);
        await kill(io, askFn: neverAsked, mode: RunMode.headless);
        expect(archives(io), hasLength(1));
      });

      test('with an empty handoff it just resets the session and keeps the link', () async {
        final io = _io(withHandoff: false);
        await kill(io, askFn: neverAsked, mode: RunMode.headless);
        expect(io.linkExists(_claudeLink), isTrue);
      });
    });
  });
}

/// Thrown by the injected exitFn so tests can assert on exit-path behaviour
/// without actually terminating the process.
class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

/// Delegates all ops to [delegate] but throws on the first write to the
/// handoff path — simulates the reset step failing.
class _FailOnResetIO implements FileIO {
  final MemoryFileIO delegate;
  _FailOnResetIO({required this.delegate});

  @override
  void write(String path, String content) {
    if (path == handoffPathFor(_workspace)) {
      throw Exception('simulated reset failure');
    }
    delegate.write(path, content);
  }

  @override
  void append(String path, String content) =>
      delegate.append(path, content);
  @override
  T withExclusiveLock<T>(String path, T Function() body) =>
      delegate.withExclusiveLock(path, body);
  @override
  String read(String path) => delegate.read(path);
  @override
  void delete(String path) => delegate.delete(path);
  @override
  bool fileExists(String path) => delegate.fileExists(path);
  @override
  bool dirExists(String path) => delegate.dirExists(path);
  @override
  void createDir(String path) => delegate.createDir(path);
  @override
  List<String> listFiles(String d, {String? extension}) =>
      delegate.listFiles(d, extension: extension);
  @override
  bool linkExists(String path) => delegate.linkExists(path);
  @override
  void deleteLink(String path) => delegate.deleteLink(path);
  @override
  void createLink(String linkPath, String targetPath) =>
      delegate.createLink(linkPath, targetPath);
}
