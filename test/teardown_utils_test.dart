import 'package:test/test.dart';
import 'package:claudart/teardown_utils.dart';

void main() {
  group('extractBranch', () {
    test('extracts branch from handoff header', () {
      const doc = '> Session started: 2026-01-01 | Branch: fix/my-bug\n';
      expect(extractBranch(doc), 'fix/my-bug');
    });

    test('returns unknown when branch not present', () {
      expect(extractBranch('no branch here'), 'unknown');
    });

    test('trims whitespace', () {
      const doc = '> Branch:   main  \n';
      expect(extractBranch(doc), 'main');
    });
  });

  group('extractSection', () {
    const doc = '''
## Debug Progress

Some progress notes.

## Other

other content
''';

    test('extracts section content', () {
      expect(extractSection(doc, 'Debug Progress'), 'Some progress notes.');
    });

    test('returns empty string when section missing', () {
      expect(extractSection(doc, 'Nonexistent'), '');
    });
  });

  group('readSubSection', () {
    const section = '''
### What was attempted
Tried adding a listener.

### What changed (files modified)
my_feature.dart
''';

    test('extracts subsection content', () {
      expect(readSubSection(section, 'What was attempted'), 'Tried adding a listener.');
    });

    test('returns fallback when subsection missing', () {
      expect(readSubSection(section, 'Missing'), '_Nothing yet._');
    });
  });

  group('appendToSection', () {
    const doc = '''## Root Cause Patterns

_No patterns recorded yet._

## Other

content
''';

    test('replaces blank placeholder with first entry', () {
      final result = appendToSection(doc, 'Root Cause Patterns', '- new pattern');
      expect(result, contains('- new pattern'));
      expect(result, isNot(contains('_No patterns recorded yet._')));
    });

    test('appends to existing entries', () {
      var result = appendToSection(doc, 'Root Cause Patterns', '- first');
      result = appendToSection(result, 'Root Cause Patterns', '- second');
      expect(result, contains('- first'));
      expect(result, contains('- second'));
    });

    test('creates new section when header not found', () {
      final result = appendToSection(doc, 'New Section', '- entry');
      expect(result, contains('## New Section'));
      expect(result, contains('- entry'));
    });

    test('replaces placeholder when blockquote metadata precedes it', () {
      const withMeta = '''## Pending

> Confirmed facts from in-progress sessions.

_Nothing yet._

## Other

content
''';
      final result = appendToSection(withMeta, 'Pending', '- new entry');
      expect(result, contains('- new entry'));
      expect(result, isNot(contains('_Nothing yet._')));
      // Blockquote metadata is preserved.
      expect(result, contains('> Confirmed facts from in-progress sessions.'));
    });

    test('appends after existing entries when section has blockquote metadata', () {
      const withMetaAndEntry = '''## Pending

> Confirmed facts from in-progress sessions.

- existing entry

## Other

content
''';
      final result = appendToSection(withMetaAndEntry, 'Pending', '- new entry');
      expect(result, contains('- existing entry'));
      expect(result, contains('- new entry'));
      expect(result, contains('> Confirmed facts from in-progress sessions.'));
    });
  });

  group('incrementHotPath', () {
    const blankSkills = '''## Hot Paths

_No sessions recorded yet._
''';

    test('adds new file with single arrow', () {
      final result = incrementHotPath(blankSkills, 'bloc', 'my_feature.dart');
      expect(result, contains('`my_feature.dart` ↑'));
      expect(result, contains('[bloc]'));
    });

    test('increments existing file arrow', () {
      var skills = incrementHotPath(blankSkills, 'bloc', 'my_feature.dart');
      skills = incrementHotPath(skills, 'bloc', 'my_feature.dart');
      expect(RegExp(r'↑+').firstMatch(skills)?.group(0)?.length, 2);
    });
  });

  group('areaFromCategory', () {
    test('api categories', () {
      expect(areaFromCategory('api-integration'), 'api');
    });

    test('concurrency categories', () {
      expect(areaFromCategory('concurrency'), 'async');
    });

    test('io categories', () {
      expect(areaFromCategory('io-filesystem'), 'io');
    });

    test('state categories', () {
      expect(areaFromCategory('state-management'), 'state');
    });

    test('config categories', () {
      expect(areaFromCategory('configuration'), 'config');
    });

    test('data categories', () {
      expect(areaFromCategory('data-parsing'), 'data');
    });

    test('unknown falls back to fix', () {
      expect(areaFromCategory('general'), 'fix');
      expect(areaFromCategory('something-else'), 'fix');
    });
  });

  group('buildCommitMessage', () {
    test('formats message without root cause', () {
      final msg = buildCommitMessage('api', 'Response not parsed correctly.', '_Not yet determined._', 'Added null check on response body');
      expect(msg, startsWith('fix(api): Response not parsed correctly'));
      expect(msg, contains('Added null check on response body'));
      expect(msg, isNot(contains('Root cause')));
    });

    test('includes root cause when known', () {
      final msg = buildCommitMessage('io', 'File not written.', 'Directory not created first.', 'Fixed it');
      expect(msg, contains('Root cause: Directory not created first'));
    });
  });

  group('firstSentence', () {
    test('returns up to first dot when short', () {
      expect(firstSentence('Widget broken. More detail here.'), 'Widget broken');
    });

    test('truncates at 72 chars when no dot', () {
      final long = 'A' * 80;
      final result = firstSentence(long);
      expect(result.length, lessThanOrEqualTo(73)); // 72 + ellipsis
      expect(result, endsWith('…'));
    });

    test('returns full string when short and no dot', () {
      expect(firstSentence('short string'), 'short string');
    });
  });

  group('archiveName', () {
    test('contains branch name with slashes replaced', () {
      final name = archiveName('fix/my-bug');
      expect(name, contains('fix_my-bug'));
      expect(name, startsWith('handoff_'));
      expect(name, endsWith('.md'));
    });

    test('replaces spaces in branch name', () {
      final name = archiveName('my branch');
      expect(name, contains('my_branch'));
    });
  });
}
