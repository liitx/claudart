// What closed a handoff, and what an automatic close may do about it (Q11, the
// evidence matrix of docs/methodical_refactor.md, written before the code). Each
// row of the matrix is one test: the evidence when the flow converges, and the
// expected exit.

import 'package:claudart/session/closure_evidence.dart';
import 'package:claudart/session/debug_disposition.dart';
import 'package:claudart/session/handoff_finding.dart';
import 'package:claudart/session/md_io.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart';
import 'package:test/test.dart';

/// A handoff with a real root cause and scope, at [status], with [disposition]
/// recorded (or none recorded when null).
SessionState _handoff(HandoffStatus status, {DebugDisposition? disposition}) {
  var content = blankHandoff;
  content = updateSection(content, 'Bug', 'The parser drops a line.');
  content = updateSection(content, 'Root Cause', 'The splitter stops early.');
  content = updateSection(
    content,
    'Scope',
    '### Files in play\n- lib/parser.dart\n\n### Must not touch\nnothing',
  );
  content = withHandoffStatus(content, status);
  if (disposition != null) content = withDebugDisposition(content, disposition);
  return SessionState.parse(content);
}

void main() {
  verifiedConsistencyTests();

  group('the evidence matrix', () {
    test('debug ran and its verification passed: teardown archives', () {
      final state = _handoff(HandoffStatus.debugComplete,
          disposition: DebugDisposition.verified);
      expect(closureEvidenceOf(state), ClosureEvidence.verified);
      expect(automaticClosureFor(ClosureEvidence.verified),
          AutomaticClosure.teardownAndArchive);
    });

    test('debug ran and its verification failed: no teardown, needsSuggest',
        () {
      // A failed verification is written as debugBlocked, never as a fix.
      final state = _handoff(HandoffStatus.needsSuggest);
      expect(closureEvidenceOf(state), ClosureEvidence.none);
      expect(automaticClosureFor(closureEvidenceOf(state)),
          AutomaticClosure.stayOpen);
    });

    test('suggest confirmed, debug skipped and recorded: teardown as a reminder',
        () {
      final state = _handoff(HandoffStatus.readyForDebug,
          disposition: DebugDisposition.skipped);
      expect(closureEvidenceOf(state), ClosureEvidence.confirmedBySuggest);
      expect(automaticClosureFor(ClosureEvidence.confirmedBySuggest),
          AutomaticClosure.teardownAsReminder);
    });

    test('suggest confirmed, nothing recorded about debug: no teardown, the '
        'owner is reminded', () {
      final state = _handoff(HandoffStatus.readyForDebug);
      expect(closureEvidenceOf(state), ClosureEvidence.debugUnrecorded);
      expect(automaticClosureFor(ClosureEvidence.debugUnrecorded),
          AutomaticClosure.remindOwner);
    });

    test('converged with no evidence at all: no teardown, it stays open', () {
      final state = SessionState.parse(blankHandoff);
      expect(closureEvidenceOf(state), ClosureEvidence.none);
      expect(automaticClosureFor(ClosureEvidence.none),
          AutomaticClosure.stayOpen);
    });
  });

  group('the evidence is read from the handoff, never guessed', () {
    test('a fix that was applied but not verified is not verified evidence',
        () {
      final state = _handoff(HandoffStatus.debugComplete,
          disposition: DebugDisposition.done);
      expect(closureEvidenceOf(state), ClosureEvidence.debugUnrecorded);
    });

    test('verified with a placeholder root cause is no evidence', () {
      var content = withHandoffStatus(blankHandoff, HandoffStatus.debugComplete);
      content = withDebugDisposition(content, DebugDisposition.verified);
      expect(closureEvidenceOf(SessionState.parse(content)), ClosureEvidence.none);
    });

    test('an investigation still under way has no evidence even if skipped is '
        'written', () {
      final state = _handoff(HandoffStatus.suggestInvestigating,
          disposition: DebugDisposition.skipped);
      expect(closureEvidenceOf(state), ClosureEvidence.none);
    });

    test('not applicable debug on a converged handoff is confirmed by suggest',
        () {
      final state = _handoff(HandoffStatus.readyForSuggest,
          disposition: DebugDisposition.notApplicable);
      expect(closureEvidenceOf(state), ClosureEvidence.confirmedBySuggest);
    });
  });

  group('every evidence decides an exit', () {
    for (final evidence in ClosureEvidence.values) {
      test('${evidence.name} has an automatic closure', () {
        expect(AutomaticClosure.values, contains(automaticClosureFor(evidence)));
      });
    }

    test('only verified evidence archives', () {
      final archiving = [
        for (final evidence in ClosureEvidence.values)
          if (automaticClosureFor(evidence) ==
              AutomaticClosure.teardownAndArchive)
            evidence,
      ];
      expect(archiving, [ClosureEvidence.verified]);
    });
  });
}

/// The disagreement rule for the verified disposition: it, like `done`, goes
/// only with a finished fix, and a finished fix goes only with one of them.
void verifiedConsistencyTests() {
  group('verified is consistent only with a finished fix', () {
    test('verified at debugComplete has no findings', () {
      final state = _handoff(HandoffStatus.debugComplete,
          disposition: DebugDisposition.verified);
      expect(state.findings, isEmpty);
    });

    test('verified at readyForDebug disagrees with its status', () {
      final state = _handoff(HandoffStatus.readyForDebug,
          disposition: DebugDisposition.verified);
      expect(state.findings, contains(HandoffFinding.debugDispositionDisagrees));
    });

    test('a finished fix recorded as skipped disagrees', () {
      final state = _handoff(HandoffStatus.debugComplete,
          disposition: DebugDisposition.skipped);
      expect(state.findings, contains(HandoffFinding.debugDispositionDisagrees));
    });
  });
}
