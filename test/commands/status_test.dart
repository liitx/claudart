import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/commands/status.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/ui/ansi.dart' as ansi;
import '../helpers/mocks.dart';
import '../matrix/handoff_expectation.dart';
import '../matrix/handoff_status_matrix.dart' as handoff_matrix;
import '../matrix/handoff_status_type.dart';

const _projectRoot = '/projects/my-app';
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
      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );
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
      await runStatus(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _throwExit,
      );
      // Status is read-only — handoff must not be mutated.
      expect(io.read(handoffPathFor(workspace)), equals(handoffBefore));
      handoff_matrix.cover(HandoffStatusType.suggestInvestigating, HandoffExpectation.suggest);
    });
  });

  group('status — error handling', () {
    test('exits 1 when no registry entry found', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });

    test('exits 1 when not in git repo and no override', () async {
      final io = MemoryFileIO();

      expect(
        () => runStatus(io: io, exitFn: _throwExit),
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', 1)),
      );
    });
  });

  group('status — models', () {
    Future<String> statusText(MemoryFileIO io) async {
      final output = <String>[];
      await runZoned(
        () => runStatus(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _throwExit,
        ),
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
      expect(out, contains('reader  haiku -> claude-new  context 25%  drift: none'));
      expect(out, contains('reasoner  haiku -> claude-b  context 25%  '
          'drift: maxOutputTokens'));
      expect(out, isNot(contains('claude-old')));
    });

    test('shows no Models section when nothing was recorded', () async {
      final out = await statusText(ioWithModels(const []));
      expect(out, isNot(contains('Models')));
    });
  });

  group('status — relevant past patterns', () {
    Future<List<String>> statusOutput(MemoryFileIO io) async {
      final output = <String>[];
      await runZoned(
        () => runStatus(io: io, projectRootOverride: _projectRoot, exitFn: _throwExit),
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
          () => runStatus(
            io: ioWith(bug: blank),
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            prompt: true,
          ),
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
          () => runStatus(
            io: io,
            projectRootOverride: _projectRoot,
            exitFn: _throwExit,
            prompt: true,
          ),
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
