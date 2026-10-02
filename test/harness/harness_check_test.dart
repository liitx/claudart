// harness_check_test.dart — one test() per HarnessCheckId/HarnessCheckResult
// variant, per dartrix's testing paradigm — a loop here would collapse
// every variant's pass/fail into one result and hide failures after the
// first.

import 'package:claudart/harness/harness_check.dart';
import 'package:test/test.dart';

void main() {
  group('HarnessCheckId.label', () {
    test('tools', () => expect(HarnessCheckId.tools.label, equals('tools')));
    test('gitIdentity', () => expect(HarnessCheckId.gitIdentity.label, equals('git identity')));
    test('ghAuth', () => expect(HarnessCheckId.ghAuth.label, equals('gh auth')));
    test('providerEnv', () => expect(HarnessCheckId.providerEnv.label, equals('provider env')));
  });

  group('HarnessCheckResult.marker', () {
    test('ok', () => expect(HarnessCheckResult.ok.marker, equals('[OK]')));
    test('skip', () => expect(HarnessCheckResult.skip.marker, equals('[SKIP]')));
    test('fail', () => expect(HarnessCheckResult.fail.marker, equals('[FAIL]')));
  });

  group('formatHarnessOutcome', () {
    test('renders marker, label, and detail as one line', () {
      const outcome = (
        id: HarnessCheckId.ghAuth,
        result: HarnessCheckResult.fail,
        detail: 'gh auth status failed — run `gh auth login`',
      );
      expect(
        formatHarnessOutcome(outcome),
        equals('[FAIL] gh auth: gh auth status failed — run `gh auth login`'),
      );
    });
  });
}
