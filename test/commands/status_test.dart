import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/commands/status.dart';
import 'package:claudart/generated/user_text.g.dart';
import 'package:claudart/logging/log_file.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/config/paths.dart';
import 'package:claudart/session/closure_evidence.dart';
import 'package:claudart/session/debug_disposition.dart';
import 'package:claudart/session/md_io.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/templates/handoff_template.dart';
import 'package:claudart/ui/ansi.dart' as ansi;
import '../helpers/mocks.dart';
import '../matrix/handoff_expectation.dart';
import '../matrix/handoff_status_matrix.dart' as handoff_matrix;
import '../matrix/handoff_status_type.dart';
import '../helpers/project_fixture.dart';
import 'package:claudart/commands/support/command_seams.dart';

const _projectRoot = ProjectFixture.root;
const _projectName = 'my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

void main() {
  handoff_matrix.assertNoGaps();

  group('status — branch display', () {
    test('displays live git branch when handoff has unknown', () async {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);

      // Registry entry.
      final registry = Registry.empty().add(RegistryEntry(
        name: _projectName,
        projectRoot: _projectRoot,
        workspacePath: workspace,
        createdAt: '2026-03-17',
        lastSession: '2026-03-17',
        sensitivityMode: false,
      ));
      registry.save(io: io);

      // Handoff with 'unknown' branch.
      const handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: unknown
> Source of truth between suggest and debug agents.

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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      // Note: projectRootOverride bypasses git detection so currentBranch
      // will be null. The command falls back to reading branch from handoff.
      // Status is read-only — it must not mutate the handoff file.
      final handoffBefore = io.read(handoffPathFor(workspace));
      await runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit));
      // Handoff must be unchanged — status is read-only.
      expect(io.read(handoffPathFor(workspace)), equals(handoffBefore));
      handoff_matrix.cover(HandoffStatusType.suggestInvestigating, HandoffExpectation.suggest);
    });

    test('displays handoff branch when git detection unavailable', () async {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);

      final registry = Registry.empty().add(RegistryEntry(
        name: _projectName,
        projectRoot: _projectRoot,
        workspacePath: workspace,
        createdAt: '2026-03-17',
        lastSession: '2026-03-17',
        sensitivityMode: false,
      ));
      registry.save(io: io);

      const handoff = '''# Agent Handoff — $_projectName

> Session started: 2026-03-17 | Branch: fix/null-ref
> Source of truth between suggest and debug agents.

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

_Nothing yet.
''';
      io.write(handoffPathFor(workspace), handoff);

      final handoffBefore = io.read(handoffPathFor(workspace));
      await runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit));
      // Status is read-only — handoff must not be mutated.
      expect(io.read(handoffPathFor(workspace)), equals(handoffBefore));
      handoff_matrix.cover(HandoffStatusType.suggestInvestigating, HandoffExpectation.suggest);
    });
  });

  group('status — error handling', () {
    test('exits 1 when no registry entry found', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit)),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });

    test('exits 1 when not in git repo and no override', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(seams: CommandSeams(io: io, exitFn: _throwExit)),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });

  group('status — models', () {
    Future<String> statusText(MemoryFileIO io) async {
      final output = <String>[];
      await runZoned(
        () => runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit)),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      return output.join('\n');
    }

    MemoryFileIO ioWithModels(List<String> records) {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);
      Registry.empty()
          .add(RegistryEntry(
            name: _projectName,
            projectRoot: _projectRoot,
            workspacePath: workspace,
            createdAt: '2026-03-17',
            lastSession: '2026-03-17',
          ))
          .save(io: io);
      io.write(
        handoffPathFor(workspace),
        '# Agent Handoff\n\n## Status\n\nsuggest-investigating\n\n---\n\n'
        '## Bug\n\nA bug.\n',
      );
      if (records.isNotEmpty) {
        io.write(
          '${logsDirFor(workspace)}/models.jsonl',
          '${records.join('\n')}\n',
        );
      }
      return io;
    }

    String record(String step, String id, {String drift = '[]'}) =>
        '{"stepId":"$step","intended":"haiku","resolved":"haiku",'
        '"drift":$drift,"contextUsedFraction":0.25,"outputCapReached":false,'
        '"observation":{"observedModelId":"$id"}}';

    test('shows the newest record per step, with intended, observed and drift',
        () async {
      final out = await statusText(ioWithModels([
        record('reader', 'claude-old'),
        record('reasoner', 'claude-b', drift: '["maxOutputTokens"]'),
        record('reader', 'claude-new'),
      ]));
      expect(out, contains('Models (newest per step):'));
      expect(
        out,
        contains(
          'reader  haiku -> claude-new  (no role recorded)  '
          'context 25%  drift: none',
        ),
      );
      expect(
        out,
        contains(
          'reasoner  haiku -> claude-b  (no role recorded)  context 25%  '
          'drift: maxOutputTokens',
        ),
      );
      expect(out, isNot(contains('claude-old')));
    });

    test('shows no Models section when nothing was recorded', () async {
      final out = await statusText(ioWithModels(const []));
      expect(out, isNot(contains('Models')));
    });

    group('timing from the logs', () {
      MemoryFileIO ioWithRows(LogFile log, List<String> rows) {
        final io = ioWithModels(const []);
        io.write(
          logFilePath(logsDirFor(workspaceFor(_projectName)), log),
          '${rows.join('\n')}\n',
        );
        return io;
      }

      String runRow(String command, int? durationMs) =>
          '{"rowKind":"run","command":"$command","outcome":"ok",'
          '"durationMs":${durationMs ?? 'null'}}';

      test('shows each command: how many runs, the latest and the slowest',
          () async {
        final out = await statusText(ioWithRows(LogFile.interactions, [
          runRow('debug', 100),
          runRow('save', 40),
          runRow('debug', 300),
          runRow('debug', 200),
        ]));
        expect(out, contains('Timing (command runs):'));
        expect(out, contains('  debug  3x, latest 200ms, slowest 300ms'));
        expect(out, contains('  save  1x, latest 40ms, slowest 40ms'));
      });

      test('a command outcome row is not a run', () async {
        final out = await statusText(ioWithRows(LogFile.interactions, [
          '{"rowKind":"outcome","command":"scan","outcome":"ok","durationMs":9}',
        ]));
        expect(out, isNot(contains('Timing')));
      });

      test('says how many timed rows could not be read, and still shows the rest',
          () async {
        final out = await statusText(ioWithRows(LogFile.interactions, [
          runRow('debug', 100),
          runRow('debug', null),
        ]));
        expect(out, contains('  debug  1x, latest 100ms, slowest 100ms'));
        expect(out, contains('timed rows that could not be read as a duration: 1'));
      });

      test('shows nothing about timing when there are no rows', () async {
        final out = await statusText(ioWithModels(const []));
        expect(out, isNot(contains('Timing')));
        expect(out, isNot(contains('could not be read')));
      });
    });
  });

  group('status — what closed the handoff', () {
    /// A handoff at [status] with a real root cause and scope, and [disposition]
    /// recorded when given.
    MemoryFileIO ioClosedBy(HandoffStatus status, DebugDisposition? disposition) {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);
      Registry.empty()
          .add(RegistryEntry(
            name: _projectName,
            projectRoot: _projectRoot,
            workspacePath: workspace,
            createdAt: '2026-03-17',
            lastSession: '2026-03-17',
          ))
          .save(io: io);
      var content = blankHandoff;
      content = updateSection(content, 'Bug', 'The parser drops a line.');
      content = updateSection(content, 'Root Cause', 'The splitter stops early.');
      content = updateSection(
        content,
        'Scope',
        '### Files in play\n- lib/parser.dart\n\n### Must not touch\nnothing',
      );
      content = withHandoffStatus(content, status);
      if (disposition != null) content = withDebugDisposition(content, disposition);
      io.write(handoffPathFor(workspace), content);
      return io;
    }

    Future<String> statusText(MemoryFileIO io) async {
      final output = <String>[];
      await runZoned(
        () => runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit)),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      return output.join('\n');
    }

    const cases = <ClosureEvidence, (HandoffStatus, DebugDisposition?)>{
      ClosureEvidence.verified:
          (HandoffStatus.debugComplete, DebugDisposition.verified),
      ClosureEvidence.confirmedBySuggest:
          (HandoffStatus.readyForDebug, DebugDisposition.skipped),
      ClosureEvidence.debugUnrecorded: (HandoffStatus.readyForDebug, null),
      ClosureEvidence.none: (HandoffStatus.suggestInvestigating, null),
    };

    group('the verification hint', () {
      String hint() => UserText.statusVerificationHint
          .format({'configPath': configPathFor(workspaceFor(_projectName))});

      test('is shown for a fix applied but never verified, with no command set',
          () async {
        final text = await statusText(
            ioClosedBy(HandoffStatus.debugComplete, DebugDisposition.done));
        expect(text, contains(hint()));
      });

      test('names the key to set and the file to set it in', () {
        expect(hint(), contains('verificationCommand'));
        expect(hint(), contains('config.json'));
      });

      test('is not shown once a verification command is set', () async {
        final io =
            ioClosedBy(HandoffStatus.debugComplete, DebugDisposition.done);
        io.write(configPathFor(workspaceFor(_projectName)),
            '{"verificationCommand": "dart test"}');
        expect(await statusText(io), isNot(contains(hint())));
      });

      test('is not shown for a verified fix', () async {
        final text = await statusText(
            ioClosedBy(HandoffStatus.debugComplete, DebugDisposition.verified));
        expect(text, isNot(contains(hint())));
      });

      test('is not shown while the fix has not been applied', () async {
        final text = await statusText(ioClosedBy(HandoffStatus.readyForDebug, null));
        expect(text, isNot(contains(hint())));
      });
    });

    test('every kind of evidence has a case', () {
      expect(cases.keys.toSet(), ClosureEvidence.values.toSet());
    });

    for (final entry in cases.entries) {
      test('${entry.key.name}: says what closed it and what an automatic '
          'close would do', () async {
        final (status, disposition) = entry.value;
        final text = await statusText(ioClosedBy(status, disposition));
        final evidence = entry.key;
        final closure = automaticClosureFor(evidence);
        expect(
          text,
          contains('Closure  : ${evidence.label} — ${closure.label}'),
        );
      });
    }
  });

  group('status — relevant past patterns', () {
    Future<List<String>> statusOutput(MemoryFileIO io) async {
      final output = <String>[];
      await runZoned(
        () => runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit)),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      return output;
    }

    MemoryFileIO ioWith({
      required String bug,
      String? skills,
      String status = 'suggest-investigating',
    }) {
      final io = MemoryFileIO();
      final workspace = workspaceFor(_projectName);
      Registry.empty()
          .add(RegistryEntry(
            name: _projectName,
            projectRoot: _projectRoot,
            workspacePath: workspace,
            createdAt: '2026-03-17',
            lastSession: '2026-03-17',
          ))
          .save(io: io);
      io.write(handoffPathFor(workspace), '''# Agent Handoff — $_projectName

## Status

$status

---

## Bug

$bug
''');
      if (skills != null) io.write(skillsPathFor(workspace), skills);
      return io;
    }

    test('shows the most relevant pattern when skills.md has a match', () async {
      final io = ioWith(
        bug: 'symlink creation crashes when the target already exists as a real directory',
        skills: '''
## Root Cause Patterns

- **symlink-management**: CLI registration crashes on an existing directory. → Fix: check before linking.
- **api-integration**: Sentinel strings reached persistence before null guards. → Fix: keep sentinels null.
''',
      );
      final output = await statusOutput(io);
      expect(output.join('\n'), contains('Relevant past patterns'));
      expect(output.join('\n'), contains('symlink-management'));
    });

    for (final status in HandoffStatus.values.where((s) => s.isPersisted)) {
      test('${status.name}: prints that status\'s next step', () async {
        final io = ioWith(bug: 'a real bug', status: status.value);
        final text = (await statusOutput(io)).join('\n');
        expect(text, contains('Next step:\n  ${status.nextStep}'));
        expect(status.nextStep.allMatches(text), hasLength(1));
      });
    }

    test('prints the bug and the root cause as written', () async {
      final io = ioWith(bug: 'the save button does nothing');
      final handoff = handoffPathFor(workspaceFor(_projectName));
      io.write(
        handoff,
        '${io.read(handoff)}\n## Root Cause\n\nthe handler is unbound\n',
      );
      final text = (await statusOutput(io)).join('\n');
      expect(text, contains('Bug      : the save button does nothing'));
      expect(text, contains('Root cause: the handler is unbound'));
    });

    test('omits the section when skills.md does not exist', () async {
      final io = ioWith(bug: 'some real bug description');
      final output = await statusOutput(io);
      expect(output.join('\n'), isNot(contains('Relevant past patterns')));
    });

    test('omits the section when the bug is still a placeholder', () async {
      final io = ioWith(
        bug: '_Not yet determined._',
        skills: '## Root Cause Patterns\n\n- **general**: some pattern. → Fix: something.\n',
      );
      final output = await statusOutput(io);
      expect(output.join('\n'), isNot(contains('Relevant past patterns')));
    });

    group('a blank handoff is not a session', () {
      // The blank handoff kill, teardown and an empty rotate leave behind
      // still has a suggest-investigating Status line; it must read as
      // no-handoff, the same status SessionState.effectiveStatus gives zedup.
      const blank = '_Not yet determined._';

      setUp(() => ansi.colorEnabledOverride = false);
      tearDown(() => ansi.colorEnabledOverride = null);

      test('the Status line reads no-handoff', () async {
        final output = await statusOutput(ioWith(bug: blank));
        expect(output.join('\n'), contains('Status   : no-handoff'));
      });

      test('no Unresolved line for a blank handoff, even if its stale Status '
          'says debug-in-progress', () async {
        final output = await statusOutput(
          ioWith(bug: blank, status: 'debug-in-progress'),
        );
        expect(output.join('\n'), isNot(contains('Unresolved:')));
      });

      test('a live debug-in-progress handoff does show it', () async {
        final output = await statusOutput(
          ioWith(bug: 'Crash on save', status: 'debug-in-progress'),
        );
        expect(output.join('\n'), contains('Unresolved:'));
      });

      test('the next step is claudart setup, not /suggest', () async {
        // After teardown a CLI-only user is told what to do next. A blank
        // handoff has nothing to suggest on: the next step is a new session.
        final output = await statusOutput(ioWith(bug: blank));
        expect(output.join('\n'), contains('Run: claudart setup'));
        expect(output.join('\n'), isNot(contains('Run /suggest')));
      });

      test('--prompt mode shows no-handoff with the inactive dot', () async {
        final captured = _CapturedStdout();
        await IOOverrides.runZoned(
          () => runStatus(seams: CommandSeams(io: ioWith(bug: blank), projectRootOverride: _projectRoot, exitFn: _throwExit), prompt: true),
          stdout: () => captured,
        );
        await captured.close();
        expect(captured.text, contains('no-handoff'));
        expect(captured.text, contains('○'));
        expect(captured.text, isNot(contains('●')));
      });
    });

    group('the status colour', () {
      setUp(() => ansi.colorEnabledOverride = true);
      tearDown(() => ansi.colorEnabledOverride = null);

      test('colours the Status line by the handoff status (cyan while '
          'exploring)', () async {
        final output = await statusOutput(ioWith(bug: 'some real bug'));
        expect(
          output.join('\n'),
          contains('Status   : ${ansi.cyan}suggest-investigating${ansi.reset}'),
        );
      });

      test('colours --prompt mode the same way', () async {
        final io = ioWith(bug: 'some real bug');
        final captured = _CapturedStdout();
        await IOOverrides.runZoned(
          () => runStatus(seams: CommandSeams(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit), prompt: true),
          stdout: () => captured,
        );
        await captured.close();
        expect(
          captured.text,
          contains('${ansi.cyan}suggest-investigating${ansi.reset}'),
        );
      });
    });
  });
}

/// Collects what a command writes straight to `stdout` (not via `print`).
class _CapturedStdout implements Stdout {
  final _buffer = StringBuffer();
  String get text => _buffer.toString();

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  Future<dynamic> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
