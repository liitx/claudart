// lifecycle_test.dart — whole-session conformance: real commands, in memory.
//
// After every step of every scenario (lifecycle_scenarios.dart), the status a
// consumer would see (the exported SessionState.effectiveStatus, the one reader
// claudart and zedup share) must equal an independent literal AND the `to` the
// command logged to transitions.jsonl: file, log and consumer view agree. The
// same scenarios run against zedup's real reader by `make consumer-check`.

import 'package:claudart/dependency_config.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/workspace/workspace_link_state.dart';
import 'package:test/test.dart';

import 'lifecycle_scenarios.dart';

void main() {
  // The lifecycle must not depend on how the project is linked or whether it
  // uses dartrix: every scenario runs in every environment with the same
  // expected statuses.
  for (final environment in lifecycleEnvironments()) {
    for (final scenario in lifecycleScenarios().entries) {
      group('${describeEnvironment(environment)}: ${scenario.key}', () {
        late final io = freshLifecycleIo(environment);

        test('starts with no handoff file: noHandoff', () {
          expect(effectiveStatusOf(io), HandoffStatus.noHandoff);
        });

        for (final step in scenario.value) {
          test('${step.name}: file, log and consumer view agree', () async {
            await quietly(() => step.run(io));
            expect(effectiveStatusOf(io), step.effective);
            if (step.logged) {
              expect(
                loggedTo(io),
                step.effective.name,
                reason: 'the logged move must land where the file says',
              );
            }
          });
        }
      });
    }
  }

  group('the environment fixture', () {
    for (final environment in lifecycleEnvironments()) {
      test('${describeEnvironment(environment)}: builds what it names', () {
        final io = freshLifecycleIo(environment);
        expect(linkStateOf(io, '/projects/my-app'), environment.link);
        expect(
          io.fileExists('/projects/my-app/pubspec.yaml'),
          environment.usesDartrix,
          reason: 'a pubspec is written only when the project uses dartrix',
        );
        if (environment.usesDartrix) {
          expect(
            detectsDartrixDependency(io.read('/projects/my-app/pubspec.yaml')),
            isTrue,
          );
        }
      });
    }

    test('the matrix is every link state x dartrix on/off', () {
      expect(
          lifecycleEnvironments(),
          hasLength(
            WorkspaceLinkState.values.length * 2,
          ));
    });
  });

  group('setup "Start fresh" over a live handoff', () {
    test(
        'lands in suggestInvestigating and is logged as a move the table '
        'lacks', () async {
      final io = freshLifecycleIo();
      await quietly(() => setupDefault(io));
      await quietly(() => suggest(io));
      expect(effectiveStatusOf(io), HandoffStatus.readyForDebug);

      await quietly(() => setupStartFresh(io));
      expect(effectiveStatusOf(io), HandoffStatus.suggestInvestigating);
      expect(loggedTo(io), isNull, reason: 'logged rejected: not in the table');
    });
  });
}
