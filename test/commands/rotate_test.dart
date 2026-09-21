import 'dart:async';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/git_utils.dart';
import 'package:claudart/templates/handoff_template.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/session/teardown_utils.dart';
import 'package:claudart/workspace/workspace_index.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _workspace = '/workspaces/my-app';

// Handoff with two pending issues.
const _handoffWithPending = '''# Agent Handoff — my-app

> Session started: 2026-03-18 | Branch: fix/pr-bugs

---

## Status

ready-for-debug

---

## Bug

Response not parsed when body is null.

---

## Expected Behavior

Parser returns null cleanly.

---

## Root Cause

Missing null guard on response.body before JSON decode.

---

## Scope

### Files in play
lib/api/response_parser.dart

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

---

## Pending Issues

> Other issues found during this session, not yet the active focus.
> claudart rotate will seed the next handoff from the first unchecked item.

- [ ] Stream fires before connection established
- [ ] Missing await on async initialiser
''';

// Handoff with no pending issues.
const _handoffNoPending = '''# Agent Handoff — my-app

> Session started: 2026-03-18 | Branch: fix/single

---

## Status

ready-for-debug

---

## Bug

Widget does not rebuild on state change.

---

## Expected Behavior

Widget rebuilds.

---

## Root Cause

Missing notifyListeners call.

---

## Scope

### Files in play
lib/widget.dart

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

---

## Pending Issues

> Other issues found during this session, not yet the active focus.

_None recorded yet._
''';

MemoryFileIO _io({String handoff = _handoffWithPending}) {
  final handoffFile = handoffPathFor(_workspace);
  const registryContent = '''
{
  "_warning": "Do not edit manually",
  "workspaces": [
    {
      "name": "my-app",
      "workspacePath": "$_workspace",
      "projectRoot": "$_projectRoot",
      "sensitivityMode": false,
      "createdAt": "2026-03-18",
      "lastSession": "2026-03-18"
    }
  ]
}
''';
  return MemoryFileIO(files: {
    handoffFile: handoff,
    p.join(workspacesRoot, 'registry.json'): registryContent,
  });
}

Future<bool> _buildOk(String _) async => true;
Future<bool> _buildFail(String _) async => false;
bool _confirmYes(String _) => true;
bool _confirmNo(String _) => false;

Never _noExit(int code) => throw StateError('exit($code) called');

void main() {
  group('runRotate — branch display', () {
    test('prefers live git branch over stale handoff branch', () async {
      final realGit = detectGitContext();
      // Only meaningful inside a real git checkout — skip otherwise.
      if (realGit == null) return;

      final io = MemoryFileIO(files: {
        handoffPathFor(_workspace): _handoffWithPending,
        p.join(workspacesRoot, 'registry.json'): '''
{
  "_warning": "Do not edit manually",
  "workspaces": [
    {
      "name": "my-app",
      "workspacePath": "$_workspace",
      "projectRoot": "${realGit.root}",
      "sensitivityMode": false,
      "createdAt": "2026-03-18",
      "lastSession": "2026-03-18"
    }
  ]
}
''',
      });

      final output = <String>[];
      await runZoned(
        () => runRotate(
          io: io,
          projectRootOverride: null,
          exitFn: _noExit,
          confirmFn: _confirmNo,
          buildFn: _buildOk,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );

      final printed = output.join('\n');
      // _handoffWithPending stores "Branch: fix/pr-bugs" — the live branch must win.
      expect(printed, contains('Branch : ${realGit.branch}'));
      expect(printed, isNot(contains('Branch : fix/pr-bugs')));
    });

    test('prints which project it resolved before doing anything', () async {
      final io = _io();
      final output = <String>[];
      await runZoned(
        () => runRotate(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _noExit,
          confirmFn: _confirmYes,
          buildFn: _buildOk,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => output.add(line),
        ),
      );
      expect(output.join('\n'), contains('Project  : my-app'));
    });
  });

  group('runRotate — no handoff', () {
    test('returns noHandoff when file missing', () async {
      final io = MemoryFileIO(files: {
        p.join(workspacesRoot, 'registry.json'): '''
{
  "_warning": "Do not edit manually",
  "workspaces": [
    {
      "name": "my-app",
      "workspacePath": "$_workspace",
      "projectRoot": "$_projectRoot",
      "sensitivityMode": false,
      "createdAt": "2026-03-18",
      "lastSession": "2026-03-18"
    }
  ]
}
''',
      });
      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      expect(result, RotateResult.noHandoff);
    });
  });

  group('runRotate — user cancels', () {
    test('returns cancelled and does not archive', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);
      final originalContent = io.files[handoffFile];

      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmNo,
        buildFn: _buildOk,
      );

      expect(result, RotateResult.cancelled);
      // Handoff untouched.
      expect(io.files[handoffFile], originalContent);
      // No archive written.
      expect(io.files.keys.where((k) => k.contains('/archive/')), isEmpty);
    });
  });

  group('runRotate — consent is never inferred from a missing terminal', () {
    test('end of input stops with exit 1 and changes nothing', () async {
      // The old behaviour was to wave a caller with no stdin through
      // ("proceeding without confirmation") and run the build gate unasked.
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);
      final original = io.files[handoffFile];
      var built = false;

      await expectLater(
        runRotate(
          io: io,
          projectRootOverride: _projectRoot,
          exitFn: _noExit,
          askFn: (_) => null,
          buildFn: (_) async => built = true,
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'exit(1) called')),
      );

      expect(built, isFalse, reason: 'the build gate must not run');
      expect(io.files[handoffFile], original);
      expect(io.files.keys.where((k) => k.contains('/archive/')), isEmpty);
    });

    test('--headless proceeds without asking', () async {
      final io = _io();
      var asked = false;

      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        askFn: (_) {
          asked = true;
          return null;
        },
        buildFn: _buildOk,
        mode: RunMode.headless,
      );

      expect(asked, isFalse);
      expect(result, isNot(RotateResult.cancelled));
      expect(io.files.keys.where((k) => k.contains('/archive/')), isNotEmpty);
    });

    test('--headless ignores an injected confirm that would say no (headless never prompts)', () async {
      final io = _io();
      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmNo,
        buildFn: _buildOk,
        mode: RunMode.headless,
      );
      expect(result, isNot(RotateResult.cancelled));
    });

    test('an explicit answer still decides, including a piped one', () async {
      final yes = await runRotate(
        io: _io(),
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        askFn: (_) => true,
        buildFn: _buildOk,
      );
      expect(yes, isNot(RotateResult.cancelled));

      final no = await runRotate(
        io: _io(),
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        askFn: (_) => false,
        buildFn: _buildOk,
      );
      expect(no, RotateResult.cancelled);
    });

    test('an injected confirmFn is asked, as before', () async {
      final result = await runRotate(
        io: _io(),
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        buildFn: _buildOk,
        confirmFn: _confirmNo,
      );
      expect(result, RotateResult.cancelled);
    });
  });

  group('runRotate — gate failure message', () {
    test('names the gate command and where to change it', () async {
      final printed = <String>[];
      late RotateResult result;
      await Zone.current
          .fork(specification: ZoneSpecification(print: (self, parent, zone, line) => printed.add(line)))
          .run(() async {
        result = await runRotate(
          io: _io(),
          projectRootOverride: _projectRoot,
          exitFn: _noExit,
          confirmFn: _confirmYes,
          buildFn: _buildFail,
        );
      });
      expect(result, RotateResult.buildFailed);
      final text = printed.join('\n');
      expect(text, contains('make rebuild'));
      expect(text, contains('afterFixCommand'));
      expect(text, contains(configPathFor(_workspace)));
    });
  });

  group('runRotate — build gate fails', () {
    test('returns buildFailed, archives handoff, does not seed new one', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);
      final originalContent = io.files[handoffFile];

      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildFail,
      );

      expect(result, RotateResult.buildFailed);
      // Archive was written before the build gate.
      expect(io.files.keys.any((k) => k.contains('/archive/')), isTrue);
      // Live handoff NOT overwritten — still original content.
      expect(io.files[handoffFile], originalContent);
    });
  });

  group('runRotate — with pending issues', () {
    test('returns rotated', () async {
      final io = _io();
      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      expect(result, RotateResult.rotated);
    });

    test('archives current handoff', () async {
      final io = _io();
      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      expect(io.files.keys.any((k) => k.contains('/archive/')), isTrue);
    });

    test('archived session is visible to `claudart archives` (index entry appended)', () async {
      final io = _io();
      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      final entries = loadIndex(_workspace, io: io);
      expect(entries, hasLength(1));
      expect(entries.first.branch, equals('fix/pr-bugs'));
    });

    test('seeds new handoff with first pending issue as Bug', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      final newHandoff = io.files[handoffFile]!;
      expect(newHandoff, contains('Stream fires before connection established'));
    });

    test('remaining issues carried to new Pending Issues section', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      final newHandoff = io.files[handoffFile]!;
      expect(newHandoff, contains('Missing await on async initialiser'));
      expect(newHandoff, isNot(contains('Stream fires before connection established\n'
          '- [ ] Missing await')));
    });

    test('first issue consumed — not in Pending Issues of new handoff', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      final pending = extractPendingIssues(io.files[handoffFile]!);
      expect(pending, ['Missing await on async initialiser']);
    });

    test('new handoff resets status to suggest-investigating', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      final newHandoff = io.files[handoffFile]!;
      expect(newHandoff, contains('suggest-investigating'));
    });

    test('branch preserved in new handoff', () async {
      final io = _io();
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      expect(io.files[handoffFile], contains('fix/pr-bugs'));
    });
  });

  group('runRotate — no pending issues', () {
    test('returns noNextIssue', () async {
      final io = _io(handoff: _handoffNoPending);
      final result = await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      expect(result, RotateResult.noNextIssue);
    });

    test('resets handoff to blank after archiving', () async {
      final io = _io(handoff: _handoffNoPending);
      final handoffFile = handoffPathFor(_workspace);

      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );

      expect(io.files[handoffFile], blankHandoff);
    });

    test('archives original handoff', () async {
      final io = _io(handoff: _handoffNoPending);
      await runRotate(
        io: io,
        projectRootOverride: _projectRoot,
        exitFn: _noExit,
        confirmFn: _confirmYes,
        buildFn: _buildOk,
      );
      expect(io.files.keys.any((k) => k.contains('/archive/')), isTrue);
    });
  });
}
