import 'dart:io';

import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/logging/logger.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_store.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/md_io.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _workspace = '/workspaces/app';
const _handoffFile = '$_workspace/handoff.md';
const _command = 'save';

String _handoffAt(HandoffStatus status) => withHandoffStatus(
      blankHandoff.replaceFirst('## Status\n\n', '## Status\n\nready-for-debug'),
      status,
    );

({HandoffStore store, MemoryFileIO io}) _store(HandoffStatus status) {
  final io = MemoryFileIO()..write(_handoffFile, _handoffAt(status));
  return (
    io: io,
    store: HandoffStore(
      io: io,
      handoffFile: _handoffFile,
      logger: SessionLogger.plain(io: io, workspacePath: _workspace),
      command: _command,
    ),
  );
}

void main() {
  group('$HandoffStore', () {
    test('apply writes the next status and returns what it wrote', () {
      final fixture = _store(HandoffStatus.readyForDebug);
      final written = fixture.store
          .apply(fixture.io.read(_handoffFile), HandoffEvent.debugStarted);
      expect(readHandoffStatus(written), HandoffStatus.debugInProgress);
      expect(fixture.io.read(_handoffFile), written);
    });

    test('apply records the move it made', () {
      final fixture = _store(HandoffStatus.readyForDebug);
      fixture.store
          .apply(fixture.io.read(_handoffFile), HandoffEvent.debugStarted);
      final log = fixture.io
          .read('$_workspace/logs/transitions.jsonl');
      expect(log, contains(HandoffEvent.debugStarted.name));
    });

    test('apply of a move the table lacks writes nothing and throws', () {
      final fixture = _store(HandoffStatus.readyForDebug);
      final before = fixture.io.read(_handoffFile);
      expect(
        () => fixture.store.apply(before, HandoffEvent.suggestResumed),
        throwsA(isA<InvalidHandoffTransitionException>()),
      );
      expect(fixture.io.read(_handoffFile), before);
    });

    test('rewrite writes content that keeps the status', () {
      final fixture = _store(HandoffStatus.readyForDebug);
      fixture.store.rewrite('${fixture.io.read(_handoffFile)}\nnote\n');
      expect(fixture.io.read(_handoffFile), endsWith('note\n'));
    });

    test('rewrite refuses content that changes the status', () {
      final fixture = _store(HandoffStatus.readyForDebug);
      final before = fixture.io.read(_handoffFile);
      expect(
        () => fixture.store
            .rewrite(withHandoffStatus(before, HandoffStatus.debugComplete)),
        throwsStateError,
      );
      expect(fixture.io.read(_handoffFile), before);
    });

    test('replace writes the content and records the move', () {
      final fixture = _store(HandoffStatus.debugComplete);
      fixture.store.replace(
        blankHandoff,
        from: HandoffStatus.debugComplete,
        event: HandoffEvent.tornDown,
      );
      expect(fixture.io.read(_handoffFile), blankHandoff);
      expect(
        fixture.io.read('$_workspace/logs/transitions.jsonl'),
        contains(HandoffEvent.tornDown.name),
      );
    });

    test('replace of a move the table lacks still writes, and logs it rejected',
        () {
      final fixture = _store(HandoffStatus.suggestInvestigating);
      fixture.store.replace(
        blankHandoff,
        from: HandoffStatus.suggestInvestigating,
        event: HandoffEvent.tornDown,
      );
      expect(fixture.io.read(_handoffFile), blankHandoff);
      expect(
        fixture.io.read('$_workspace/logs/transitions.jsonl'),
        contains('"rejected":true'),
      );
    });

    test('apply publishes the move to observers', () async {
      final fixture = _store(HandoffStatus.readyForDebug);
      final seen = <HandoffEvent>[];
      fixture.store.bus.transitions.listen((move) => seen.add(move.event));
      fixture.store
          .apply(fixture.io.read(_handoffFile), HandoffEvent.debugStarted);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [HandoffEvent.debugStarted]);
    });

    test('an event a reaction returns is applied by the store, after the move',
        () async {
      final fixture = _store(HandoffStatus.debugInProgress);
      fixture.store.react(
        'close',
        (move) async =>
            move.event == HandoffEvent.fixApplied ? HandoffEvent.tornDown : null,
      );
      fixture.store
          .apply(fixture.io.read(_handoffFile), HandoffEvent.fixApplied);
      await fixture.store.drain();
      // A blank handoff is the status noHandoff, which is never written itself.
      expect(fixture.io.read(_handoffFile), blankHandoff);
      expect(
        SessionState.parse(fixture.io.read(_handoffFile)).effectiveStatus,
        HandoffStatus.noHandoff,
      );
      final events = RegExp(r'"event":"(\w+)"')
          .allMatches(fixture.io.read('$_workspace/logs/transitions.jsonl'))
          .map((match) => match.group(1))
          .toList();
      expect(events, [
        HandoffEvent.fixApplied.name,
        HandoffEvent.tornDown.name,
      ]);
    });

    test('a reaction that throws is logged under its failure type', () async {
      final fixture = _store(HandoffStatus.readyForDebug);
      fixture.store.react('breaks', (move) async => throw StateError('boom'));
      fixture.store
          .apply(fixture.io.read(_handoffFile), HandoffEvent.debugStarted);
      await fixture.store.drain();
      expect(
        fixture.io.read('$_workspace/logs/errors.jsonl'),
        contains(FailureType.handoffListenerFailed.name),
      );
      expect(readHandoffStatus(fixture.io.read(_handoffFile)),
          HandoffStatus.debugInProgress);
    });

    test('replace of a legal move records it once', () {
      final fixture = _store(HandoffStatus.debugComplete);
      fixture.store.replace(
        blankHandoff,
        from: HandoffStatus.debugComplete,
        event: HandoffEvent.tornDown,
      );
      final lines = fixture.io
          .read('$_workspace/logs/transitions.jsonl')
          .trim()
          .split('\n');
      expect(lines, hasLength(1));
    });

    test('writeBlank writes the blank handoff', () {
      final io = MemoryFileIO();
      HandoffStore.writeBlank(io, _handoffFile);
      expect(io.read(_handoffFile), blankHandoff);
    });
  });

  group('who writes the handoff', () {
    /// Files that write the handoff themselves, each with its reason.
    /// `flow` writes the agent-constructed handoff, whose status is outside the
    /// transition table (docs/design.md): it has no event to record.
    const ledger = {'lib/commands/flow.dart'};
    final write = RegExp(
      r'\.write\(\s*(handoffFile|handoffPath|handoffPathFor\()',
    );

    List<String> writers(Map<String, String> sources) => [
          for (final entry in sources.entries)
            if (entry.key != 'lib/session/handoff_store.dart' &&
                write.hasMatch(entry.value))
              entry.key,
        ]..sort();

    test('a file writing handoff.md directly is found', () {
      expect(
        writers({'lib/a.dart': 'io.write(handoffFile, text);'}),
        ['lib/a.dart'],
      );
    });

    test('only the store writes handoff.md, and the ledger says why not', () {
      final sources = {
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          file.path: file.readAsStringSync(),
      };
      expect(writers(sources).toSet().difference(ledger), isEmpty);
    });
  });
}
