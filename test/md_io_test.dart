import 'dart:io';
import 'package:claudart/session/handoff_event.dart';
import 'package:claudart/session/handoff_transition.dart';
import 'package:claudart/session/invalid_handoff_transition_exception.dart';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';
import 'package:claudart/md_io.dart';
import 'helpers/mocks.dart';

void main() {
  group('readSection', () {
    const doc = '''
## Bug

Widget does not update on state change.

---

## Root Cause

The state listener is not attached.

---

## Other

some content
''';

    test('returns trimmed section content', () {
      expect(readSection(doc, 'Bug'), 'Widget does not update on state change.');
    });

    test('strips trailing separator', () {
      expect(readSection(doc, 'Bug'), isNot(contains('---')));
    });

    test('returns fallback when section missing', () {
      expect(readSection(doc, 'Nonexistent'), '_Not yet determined._');
    });

    test('reads last section without trailing separator', () {
      expect(readSection(doc, 'Other'), 'some content');
    });
  });

  group('updateSection', () {
    const doc = '## Status\n\nold-status\n\n## Other\n\ncontent\n';

    test('replaces existing section content', () {
      final result = updateSection(doc, 'Status', 'new-status');
      expect(result, contains('new-status'));
      expect(result, isNot(contains('old-status')));
    });

    test('appends new section when not found', () {
      final result = updateSection(doc, 'Missing', 'added');
      expect(result, contains('## Missing'));
      expect(result, contains('added'));
    });
  });

  group('readStatus', () {
    test('extracts status value', () {
      const doc = '## Status\n\nsuggest-investigating\n';
      expect(readStatus(doc), 'suggest-investigating');
    });

    test('returns unknown when missing', () {
      expect(readStatus('no status here'), 'unknown');
    });
  });

  group('updateStatus', () {
    test('replaces status value', () {
      const doc = '## Status\n\nsuggest-investigating\n';
      // The deprecated raw writer is still exported; this pins its behavior.
      // ignore: deprecated_member_use_from_same_package
      final result = updateStatus(doc, 'ready-for-debug');
      expect(result, contains('ready-for-debug'));
      expect(result, isNot(contains('suggest-investigating')));
    });
  });

  group('typed handoff status', () {
    const doc = '## Status\n\nsuggest-investigating\n';
    final persisted = HandoffStatus.values.where((s) => s.isPersisted);

    for (final status in persisted) {
      test('${status.name}: write then read round-trips', () {
        final written = withHandoffStatus(doc, status);
        expect(readHandoffStatus(written), status);
        expect(readStatus(written), status.value);
      });
    }

    for (final status in HandoffStatus.values.where((s) => !s.isPersisted)) {
      test('${status.name}: display-only, refused on write', () {
        expect(
          () => withHandoffStatus(doc, status),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'status')
                .having(
                  (e) => e.message,
                  'message',
                  'display-only, never written to disk',
                ),
          ),
        );
      });
    }

    test('readHandoffStatus maps a missing status to unknown', () {
      expect(readHandoffStatus('no status here'), HandoffStatus.unknown);
    });

    test('isPersisted: exactly noHandoff and unknown are display-only', () {
      expect(
        HandoffStatus.values.where((s) => !s.isPersisted).toSet(),
        {HandoffStatus.noHandoff, HandoffStatus.unknown},
      );
    });
  });

  group('applyHandoffEvent', () {
    String docIn(HandoffStatus status) => '## Status\n\n${status.value}\n';

    test('applies a legal event: the status becomes the transition target', () {
      final result = applyHandoffEvent(
        docIn(HandoffStatus.readyForDebug),
        HandoffEvent.debugStarted,
      );
      expect(readHandoffStatus(result), HandoffStatus.debugInProgress);
    });

    test('a self-loop event leaves the status as it was', () {
      final result = applyHandoffEvent(
        docIn(HandoffStatus.suggestInvestigating),
        HandoffEvent.saveUnconfirmed,
      );
      expect(readHandoffStatus(result), HandoffStatus.suggestInvestigating);
    });

    test('rejects a move the transition table lacks, naming status and event',
        () {
      expect(
        () => applyHandoffEvent(
          docIn(HandoffStatus.debugComplete),
          HandoffEvent.debugStarted,
        ),
        throwsA(
          isA<InvalidHandoffTransitionException>()
              .having((e) => e.from, 'from', HandoffStatus.debugComplete)
              .having((e) => e.event, 'event', HandoffEvent.debugStarted),
        ),
      );
    });

    test('reports the transition it applied to onTransition, once', () {
      final seen = <HandoffTransition>[];
      applyHandoffEvent(
        docIn(HandoffStatus.readyForDebug),
        HandoffEvent.debugStarted,
        onTransition: seen.add,
      );
      expect(seen, [
        const HandoffTransition(
          from: HandoffStatus.readyForDebug,
          event: HandoffEvent.debugStarted,
          to: HandoffStatus.debugInProgress,
        ),
      ]);
    });

    test('a rejected move reports nothing to onTransition', () {
      final seen = <HandoffTransition>[];
      expect(
        () => applyHandoffEvent(
          docIn(HandoffStatus.debugComplete),
          HandoffEvent.debugStarted,
          onTransition: seen.add,
        ),
        throwsA(isA<InvalidHandoffTransitionException>()),
      );
      expect(seen, isEmpty);
    });

    test('an unrecognised status in the file rejects every event', () {
      expect(
        () => applyHandoffEvent('## Status\n\nbogus\n', HandoffEvent.setup),
        throwsA(isA<InvalidHandoffTransitionException>()),
      );
    });
  });

  group('readFile / writeFile (real disk via temp dir)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('claudart_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writeFile creates file and readFile returns its content', () {
      final path = '${tmp.path}/test.md';
      writeFile(path, 'hello');
      expect(readFile(path), 'hello');
    });

    test('writeFile creates missing parent directories', () {
      final path = '${tmp.path}/deep/nested/file.md';
      writeFile(path, 'content');
      expect(File(path).existsSync(), isTrue);
    });

    test('readFile returns empty string for missing file', () {
      expect(readFile('${tmp.path}/missing.md'), '');
    });
  });

  group('MemoryFileIO', () {
    test('write then read returns content', () {
      final io = MemoryFileIO();
      io.write('/a.md', 'hello');
      expect(io.read('/a.md'), 'hello');
    });

    test('fileExists returns false before write', () {
      expect(MemoryFileIO().fileExists('/x.md'), isFalse);
    });

    test('fileExists returns true after write', () {
      final io = MemoryFileIO();
      io.write('/x.md', '');
      expect(io.fileExists('/x.md'), isTrue);
    });

    test('dirExists returns true for created dir', () {
      final io = MemoryFileIO();
      io.createDir('/my/dir');
      expect(io.dirExists('/my/dir'), isTrue);
    });

    test('listFiles returns only direct children with extension', () {
      final io = MemoryFileIO(files: {
        '/dir/a.md': '',
        '/dir/b.md': '',
        '/dir/sub/c.md': '',
        '/dir/d.txt': '',
      });
      final result = io.listFiles('/dir', extension: '.md');
      expect(result, containsAll(['/dir/a.md', '/dir/b.md']));
      expect(result, isNot(contains('/dir/sub/c.md')));
      expect(result, isNot(contains('/dir/d.txt')));
    });
  });
}
