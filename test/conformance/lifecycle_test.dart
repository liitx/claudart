// lifecycle_test.dart — whole-session conformance: real commands, in memory.
//
// After every step of every scenario (lifecycle_scenarios.dart), the status a
// consumer would see (the exported SessionState.effectiveStatus, the one reader
// claudart and zedup share) must equal an independent literal AND the `to` the
// command logged to transitions.jsonl: file, log and consumer view agree. The
// same scenarios run against zedup's real reader by `make consumer-check`.

import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

import 'lifecycle_scenarios.dart';

void main() {
  for (final scenario in lifecycleScenarios().entries) {
    group(scenario.key, () {
      late final io = freshLifecycleIo();

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
