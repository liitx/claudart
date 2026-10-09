import 'dart:io';
import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/templates/readme_template.dart';
import 'package:test/test.dart';

/// Verifies README.md stays 1:1 with the codebase.
///
/// The README is a single-page narrative (see the `docs/readme-rewrite` commit
/// "rewrite README — single-page, diagram + proof heavy, Phase 5 deferred to
/// PLAN"). It documents shipped surface only and intentionally carries **no**
/// per-enum glossary — the HandoffStatus / AgentFlow variant taxonomy lives in
/// PLAN.md, and deferred flows (e.g. guiDesign) are deliberately not advertised
/// here. The three sync guarantees that actually matter for that form:
///
/// 1. Command routing — every `claudart X` in the README dispatches in
///    bin/claudart.dart.
/// 2. File references — every .dart file the prose names exists on disk. The
///    Roadmap section is excluded: it legitimately names planned, not-yet-built
///    files (e.g. `planner.dart`).
/// 3. Roadmap content parity — the generated block (`roadmap.json`'s rows
///    fed through `readmeTemplate`) matches what's actually spliced into
///    README.md at the `<!-- claudart:link:roadmap -->` marker. Catches the
///    two ways this could drift: `claudart link` not run after
///    `roadmap.json` changes, or a manual edit to README.md's Roadmap table
///    that bypasses the generator. `roadmap.json` is git-committed
///    (unlike workspace.json, which lives outside the repo entirely) so
///    this check is portable to CI and a fresh clone.
///
/// Run: CLAUDART_WORKSPACE=/tmp/claudart_test dart test test/readme_sync_test.dart
void main() {
  late String readme;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
  });

  group('Command routing sync', () {
    // Test registration runs before setUpAll — read the file directly here
    // rather than relying on the shared `readme` late variable.
    // Matches "`claudart X`" — single-word sub-commands. Excludes the bare
    // "`claudart`" launcher and multi-word forms (the base command is still
    // captured).
    final readmeCmds = RegExp(r'`claudart (\w[\w-]*)`')
        .allMatches(File('README.md').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();

    for (final cmd in readmeCmds) {
      test(
          '`claudart $cmd` dispatches (ClaudartCommand or the version '
          'early-exit)', () {
        // `version` is handled and exits before dispatch ever runs — not a
        // ClaudartCommand variant, see claudart_command.dart's own doc.
        final dispatches =
            cmd == 'version' || ClaudartCommand.fromString(cmd) != null;
        expect(
          dispatches,
          isTrue,
          reason: 'Command `$cmd` appears in the README but has no '
              'ClaudartCommand variant. Add it or remove the row.',
        );
      });
    }
  });

  group('File reference sync', () {
    test(
        'every .dart file referenced in the prose exists under lib/, bin/, or tool/ '
        '(Roadmap excluded)', () {
      // The Roadmap names planned files that intentionally do not exist yet.
      final prose = readme.replaceAll(
        RegExp(r'\n## Roadmap\b.*?(?=\n## )', dotAll: true),
        '\n',
      );

      final dartFiles = [
        ...Directory('lib').listSync(recursive: true),
        ...Directory('bin').listSync(recursive: true),
        ...Directory('tool').listSync(recursive: true),
      ].whereType<File>().map((f) => f.path).toList();

      final refs = RegExp(r'[A-Za-z0-9_/]+\.dart')
          .allMatches(prose)
          .map((m) => m.group(0)!.split('/').last)
          .toSet();

      for (final basename in refs) {
        expect(
          dartFiles.any((f) => f.endsWith('/$basename')),
          isTrue,
          reason: '`$basename` is referenced in README.md prose but does not '
              'exist under lib/, bin/, or tool/. Fix or remove the reference.',
        );
      }
    });
  });

  group('Roadmap content parity', () {
    test(
        'README.md\'s spliced Roadmap block matches readmeTemplate(...) fed '
        'roadmap.json', () {
      final roadmapJson = File('roadmap.json').readAsStringSync();
      final config = parseRoadmapConfig(roadmapJson);
      expect(
        config,
        isNotNull,
        reason: 'roadmap.json is missing or malformed — could not parse '
            'a RoadmapConfig from it.',
      );

      final match = roadmapMarker.firstMatch(readme);
      expect(
        match,
        isNotNull,
        reason: 'README.md is missing the `<!-- claudart:link:roadmap -->` '
            'marker — `claudart link` will silently skip regenerating the '
            'Roadmap table.',
      );
      final actual = match!.group(0);
      final expected = readmeTemplate(
        roadmapRows: config!.rows,
        summaryText: config.summaryText ?? "What's coming",
        footerLine: config.footerLine,
      );
      expect(
        actual,
        equals(expected),
        reason: 'README.md\'s Roadmap table has drifted from roadmap.json — '
            'run `claudart link` to regenerate, or the table was hand-edited.',
      );
    });
  });
}
