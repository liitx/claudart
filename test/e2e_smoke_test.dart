import 'package:test/test.dart';
import 'package:claudart/commands/save.dart';
import 'package:claudart/commands/teardown.dart' show runTeardown, TeardownCategory;
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:path/path.dart' as p;
import 'helpers/mocks.dart';

const _root = '/e2e/claudart';
const _ws   = '/e2e/ws/claudart';

const _handoff = '''# Agent Handoff — claudart

> Session started: 2026-03-17 | Branch: main

---

## Status

debug-in-progress

---

## Bug

Arrow keys do not move cursor in text prompts.

---

## Expected Behavior

Left/right arrows reposition cursor within typed text.

---

## Root Cause

stdin.readLineSync uses cooked mode which has no readline cursor support.

---

## Scope

### Files in play
lib/md_io.dart, lib/ui/line_editor.dart

### BLoCs / providers in play
_Not yet determined._

### Classes / methods in play
prompt(), readLine()

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
Replaced stdin.readLineSync with raw-mode line editor.

### What changed (files modified)
lib/ui/line_editor.dart
lib/md_io.dart
lib/commands/kill.dart
lib/commands/link.dart

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';

MemoryFileIO _makeIO() {
  final entry = RegistryEntry(
    name: 'claudart',
    projectRoot: _root,
    workspacePath: _ws,
    createdAt: '2026-01-01',
    lastSession: '2026-03-17',
  );
  final io = MemoryFileIO(files: {handoffPathFor(_ws): _handoff});
  Registry.empty().add(entry).save(io: io);
  return io;
}

List<String> _checkpoints(MemoryFileIO io) => io.files.keys
    .where((k) =>
        k.startsWith(p.join(_ws, 'archive')) &&
        p.basename(k).startsWith('checkpoint_'))
    .toList();

List<String> _archives(MemoryFileIO io) => io.files.keys
    .where((k) =>
        k.startsWith(p.join(_ws, 'archive')) &&
        p.basename(k).startsWith('handoff_'))
    .toList();

String? Function(String, {bool optional}) _prompts(List<String?> queue) {
  final iter = queue.iterator;
  return (String _, {bool optional = false}) {
    if (!iter.moveNext()) return null;
    return iter.current;
  };
}

void main() {
  group('e2e — save → teardown full workflow', () {
    test('save writes checkpoint with branch name and root cause in skills', () async {
      final io = _makeIO();
      final result = await runSave(
        io: io,
        projectRootOverride: _root,
        exitFn: (c) => throw Exception('exit($c)'),
      );
      expect(result, equals(SkillsUpdateResult.written));

      final cps = _checkpoints(io);
      expect(cps, hasLength(1));
      expect(p.basename(cps.first), contains('main'));

      final skills = io.read(skillsPathFor(_ws));
      expect(skills, contains('cooked mode')); // root cause in pending
    });

    test('teardown after save: archives handoff, resets it, updates skills with pre-populated values', () async {
      final io = _makeIO();
      // First save to produce a checkpoint and seed skills.
      await runSave(
        io: io,
        projectRootOverride: _root,
        exitFn: (c) => throw Exception('exit($c)'),
      );

      // Teardown — hotFiles and pattern answers are null → accept pre-populated defaults.
      await runTeardown(
        io: io,
        projectRootOverride: _root,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'Replaced stdin.readLineSync with raw-mode line editor.',  // fixSummary
          null,  // hotFiles — accept default (lib/ui/line_editor.dart etc.)
          null,  // coldFiles — skip
          null,  // pattern — accept default (root cause text)
          'Implement raw-mode line editor with ESC sequence handling.',
        ]),
        pickFn: (_) => TeardownCategory.stateManagement.index,
        exitFn: (c) => throw Exception('exit($c)'),
      );

      // Archive written.
      final arcs = _archives(io);
      expect(arcs, hasLength(1));
      expect(p.basename(arcs.first), contains('main'));
      expect(io.read(arcs.first), contains('Arrow keys do not move cursor'));

      // Handoff reset — original bug text gone.
      expect(io.read(handoffPathFor(_ws)), isNot(contains('Arrow keys')));

      // Skills updated with teardown entries.
      final skills = io.read(skillsPathFor(_ws));
      expect(skills, contains('state-management'));           // category
      expect(skills, contains('cooked mode'));                // pre-populated pattern from root cause
      expect(skills, contains('line_editor'));                // pre-populated hot file from changedFiles
      expect(skills, contains('resolved'));                   // session index
    });

    test('save checkpoint is preserved after teardown (audit trail)', () async {
      final io = _makeIO();
      await runSave(
        io: io,
        projectRootOverride: _root,
        exitFn: (c) => throw Exception('exit($c)'),
      );
      await runTeardown(
        io: io,
        projectRootOverride: _root,
        confirmFn: (_) => true,
        promptFn: _prompts([
          'Fixed it.', null, null, null, 'Use line editor.',
        ]),
        pickFn: (_) => TeardownCategory.stateManagement.index,
        exitFn: (c) => throw Exception('exit($c)'),
      );

      // Both checkpoint and archive should coexist.
      expect(_checkpoints(io), hasLength(1));
      expect(_archives(io), hasLength(1));
    });
  });
}
