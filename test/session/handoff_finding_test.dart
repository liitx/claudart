// handoff_finding_test.dart — the ways a handoff's status and content disagree.

import 'package:claudart/session/handoff_finding.dart';
import 'package:test/test.dart';

/// Independent literals: what each disagreement says.
const _description = <HandoffFinding, String>{
  HandoffFinding.statusAheadOfContent: 'The status says the knowledge transfer '
      'is complete, but the root cause or scope is still a placeholder.',
  HandoffFinding.contentAheadOfStatus: 'The root cause and scope are filled '
      'in, but the status still says the knowledge transfer is in progress.',
  HandoffFinding.debugDispositionDisagrees: 'The recorded debug disposition '
      'does not match the status: only a finished fix is done.',
};

void main() {
  group('$HandoffFinding.description', () {
    test('every finding has a pinned description', () {
      expect(_description.keys.toSet(), HandoffFinding.values.toSet());
    });

    for (final finding in HandoffFinding.values) {
      test(finding.name, () {
        expect(finding.description, _description[finding]);
      });
    }
  });
}
