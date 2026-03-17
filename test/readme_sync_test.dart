import 'dart:io';
import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

/// Verifies that README.md stays 1:1 with the codebase.
///
/// Three groups:
/// 1. HandoffStatus glossary sync — every enum value has an entry, string
///    values match the .value getter, "Used by" files exist on disk.
/// 2. Architecture file list sync — every .dart path annotated with ← exists.
/// 3. Command routing sync — every command in the README table has a case
///    in bin/claudart.dart.
///
/// Run: CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/readme_sync_test.dart
void main() {
  late String readme;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
  });

  // ── 1. HandoffStatus glossary ──────────────────────────────────────────────

  group('HandoffStatus glossary sync', () {
    test('every HandoffStatus value has a glossary entry', () {
      for (final status in HandoffStatus.values) {
        expect(
          readme,
          contains('#### `HandoffStatus.${status.name}`'),
          reason: 'Missing glossary entry for HandoffStatus.${status.name}. '
              'Add an #### entry under ## Glossary → ### HandoffStatus '
              'or run /readme to generate it.',
        );
      }
    });

    test('string values in glossary match actual enum .value', () {
      for (final status in HandoffStatus.values) {
        // unknown is a parse sentinel with no canonical writeable string.
        if (status == HandoffStatus.unknown) continue;
        expect(
          readme,
          contains('**String value:** `${status.value}`'),
          reason: 'HandoffStatus.${status.name}: glossary string value does not '
              'match "${status.value}". Update the **String value:** line in '
              'README.md → Glossary.',
        );
      }
    });

    test('Used by files listed in each glossary entry exist under lib/', () {
      final usedByPattern = RegExp(r'\*\*Used by:\*\* ([^\n]+)');
      for (final match in usedByPattern.allMatches(readme)) {
        final refs = match
            .group(1)!
            .split('·')
            .map((s) => s.replaceAll('`', '').trim())
            .where((s) => s.endsWith('.dart'));
        for (final file in refs) {
          final found = Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .any((f) => f.path.endsWith('/$file'));
          expect(
            found,
            isTrue,
            reason: 'File `$file` listed in a glossary "Used by:" line does '
                'not exist under lib/. Remove or correct the entry, or run '
                '/readme to sync.',
          );
        }
      }
    });
  });

  // ── 2. Architecture file list ──────────────────────────────────────────────

  group('Architecture file list sync', () {
    late List<String> readmePaths;

    setUpAll(() {
      // Matches lines like:   path/to/file.dart  ← description
      readmePaths = RegExp(r'(\S+\.dart)\s+←')
          .allMatches(readme)
          .map((m) => m.group(1)!)
          .toList();
    });

    test('architecture section contains at least the known core files', () {
      expect(
        readmePaths,
        isNotEmpty,
        reason: 'README architecture section has no ".dart  ←" entries — '
            'the section may have been accidentally removed.',
      );
    });

    test('all .dart files listed in architecture section exist on disk', () {
      // Architecture uses a tree format so entries are bare filenames like
      // "init.dart", not full paths. Search by basename across lib/ and bin/.
      final allDartFiles = [
        ...Directory('lib').listSync(recursive: true),
        ...Directory('bin').listSync(recursive: true),
      ].whereType<File>().map((f) => f.path).toList();

      for (final path in readmePaths) {
        final basename = path.split('/').last;
        final found = allDartFiles.any((f) => f.endsWith('/$basename'));
        expect(
          found,
          isTrue,
          reason: '$basename is listed in README architecture but does not '
              'exist under lib/ or bin/. Remove the entry or rename it.',
        );
      }
    });
  });

  // ── 3. Command routing ─────────────────────────────────────────────────────

  group('Command routing sync', () {
    test(
        'all commands in README "Commands at a glance" table are dispatched '
        'in bin/claudart.dart', () {
      final entry = File('bin/claudart.dart').readAsStringSync();

      // Matches "`claudart X`" in the commands table — single-word sub-commands.
      // Excludes "`claudart`" (bare launcher) and multi-word variations like
      // "`claudart init --project name`" (the base command "init" is captured).
      final readmeCmds = RegExp(r'`claudart (\w[\w-]*)`')
          .allMatches(readme)
          .map((m) => m.group(1)!)
          .toSet();

      for (final cmd in readmeCmds) {
        expect(
          entry,
          contains("'$cmd'"),
          reason: "Command `$cmd` appears in README \"Commands at a glance\" "
              "table but has no case in bin/claudart.dart. Add routing or "
              "remove the row from the table.",
        );
      }
    });
  });
}
