// test_homes_test.dart — every library file has a test home, and the exceptions
// can only shrink.
//
// The convention of both repositories: `lib/foo/bar.dart` is tested by
// `test/foo/bar_test.dart`. A file whose test sits at another path, or that has
// no test of its own name, is named below; a name that no longer applies fails,
// so the lists are the debt and not an excuse. The line-mutation ledger
// (`make proof-changed`) needs each file's home to know which test to run first.
//
// Measured 2026-11-10 against a full coverage run.

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/proof_audit/mirror.dart';

/// Why a library file has no test of its own name.
enum NoOwnTestReason {
  /// Only declarations (enums, constants, exports): nothing executable to test.
  declarationsOnly,

  /// Fully run by the tests of the code that uses it, with no test of its own.
  exercisedByOtherTests,

  /// Run by other tests, but part of it by none (see the coverage run).
  partlyExercised,

  /// No test loads it at all: an untested command.
  neverRun,
}

/// Files tested under a different path than the one the convention names. Move
/// the test (or the file) and remove the name.
const _homeNotMirrored = {
  'lib/commands/support/claudart_command.dart',
  'lib/commands/support/command_seams.dart',
  'lib/commands/support/failure_boundary.dart',
  'lib/commands/support/interaction_boundary.dart',
  'lib/commands/support/project_resolution.dart',
  'lib/commands/support/project_selector.dart',
  'lib/commands/support/scope_files.dart',
  'lib/config/config.dart',
  'lib/config/dependency_config.dart',
  'lib/config/environment.dart',
  'lib/config/paths.dart',
  'lib/io/exit_reason.dart',
  'lib/io/file_io.dart',
  'lib/io/git_utils.dart',
  'lib/io/process_runner.dart',
  'lib/pipeline/agents/path_heuristic.dart',
  'lib/project/ignore_rules.dart',
  'lib/project/knowledge_templates.dart',
  'lib/project/portability_gap.dart',
  'lib/project/pubspec_utils.dart',
  'lib/session/md_io.dart',
};

/// Files with no test of their name, and why. Each name leaves as the file gets
/// a test of its own.
const _noOwnTest = <String, NoOwnTestReason>{
  // declarationsOnly
  'lib/assets/corpus.dart': NoOwnTestReason.declarationsOnly,
  'lib/claudart.dart': NoOwnTestReason.declarationsOnly,
  'lib/generated/dependency_config.g.dart': NoOwnTestReason.declarationsOnly,
  'lib/logging/recorded_outcome.dart': NoOwnTestReason.declarationsOnly,
  'lib/pipeline/flows/save_steps.dart': NoOwnTestReason.declarationsOnly,
  'lib/pipeline/flows/setup_steps.dart': NoOwnTestReason.declarationsOnly,
  'lib/pipeline/step_mode.dart': NoOwnTestReason.declarationsOnly,
  'lib/session/handoff_event.dart': NoOwnTestReason.declarationsOnly,
  'lib/session/run_mode.dart': NoOwnTestReason.declarationsOnly,
  'lib/version.dart': NoOwnTestReason.declarationsOnly,
  // exercisedByOtherTests
  'lib/commands/map_cmd.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/commands/support/live_handoff.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/generated/user_text.g.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/io/process_exit.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/logging/mermaid_page.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/pipeline/agents/categorization.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/pipeline/flows/teardown_steps.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/pipeline/step_result.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/pipeline/step_route.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/pipeline/step_telemetry.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/templates/command_template_marker.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/ui/styled_text.dart': NoOwnTestReason.exercisedByOtherTests,
  'lib/util/prompt_with_default.dart': NoOwnTestReason.exercisedByOtherTests,
  // partlyExercised
  'lib/logging/log_protection.dart': NoOwnTestReason.partlyExercised,
  'lib/pipeline/pipeline_context.dart': NoOwnTestReason.partlyExercised,
  'lib/pipeline/pipeline_slot.dart': NoOwnTestReason.partlyExercised,
  'lib/scanner/scan_threshold_exception.dart': NoOwnTestReason.partlyExercised,
  'lib/templates/readme_template.dart': NoOwnTestReason.partlyExercised,
  'lib/ui/ansi.dart': NoOwnTestReason.partlyExercised,
  'lib/ui/menu.dart': NoOwnTestReason.partlyExercised,
  // neverRun
  'lib/commands/experiment.dart': NoOwnTestReason.neverRun,
  'lib/commands/init.dart': NoOwnTestReason.neverRun,
};

List<String> _libFiles() => [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity.path,
    ]..sort();

void main() {
  final notMirrored = <String>{};
  final noHome = <String>{};
  for (final file in _libFiles()) {
    final home = homeTest('.', file);
    if (home == null) {
      noHome.add(file);
    } else if (!home.mirrored) {
      notMirrored.add(file);
    }
  }

  group('where each library file is tested', () {
    test('the files tested under another path are exactly the named ones', () {
      expect(notMirrored, _homeNotMirrored,
          reason: 'move the test to the mirrored path and remove the name, or '
              'name a new file that is tested elsewhere');
    });

    test('the files with no test of their name are exactly the named ones', () {
      expect(noHome, _noOwnTest.keys.toSet(),
          reason: 'a new file needs test/<path>_test.dart; a file that got one '
              'must leave _noOwnTest');
    });

    test('a file is not named in both lists', () {
      expect(_homeNotMirrored.intersection(_noOwnTest.keys.toSet()), isEmpty);
    });
  });

  group('the files no test loads', () {
    final neverRun = {
      for (final entry in _noOwnTest.entries)
        if (entry.value == NoOwnTestReason.neverRun) entry.key,
    };

    for (final file in neverRun) {
      test('$file is named as never run, so a test that loads it must remove it', () {
        final loaded = Directory('test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .any((f) => f.readAsStringSync().contains(file.replaceFirst('lib/', 'package:claudart/')));
        expect(loaded, isFalse);
      });
    }
  });
}
