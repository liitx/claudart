import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/handoff_template.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/teardown_utils.dart';
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
