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

import '../helpers/spec_obligations.dart';
import '../helpers/test_trace.dart';

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
    /// One row of the matrix as a traced check: the handoff it is given, the
    /// evidence and the exit expected for it, taken before the code runs.
    void row(
      String name,
      SessionState state, {
      required ClosureEvidence evidence,
      required AutomaticClosure closure,
    }) =>
        test(name, () {
          final check = tracer.check(
            label: name,
            input: '${state.effectiveStatus.name}, '
                'debug ${state.debugDisposition.name}',
            expected: '${evidence.name} -> ${closure.name}',
            obligation: SpecObligation.headlessClosesOnlyOnVerified,
          );
          final found = closureEvidenceOf(state);
          check.verify('${found.name} -> ${automaticClosureFor(found).name}');
        });

    row(
      'debug ran and its verification passed: teardown archives',
      _handoff(HandoffStatus.debugComplete,
          disposition: DebugDisposition.verified),
      evidence: ClosureEvidence.verified,
      closure: AutomaticClosure.teardownAndArchive,
    );
    // A failed verification is written as debugBlocked, never as a fix.
    row(
      'debug ran and its verification failed: no teardown, needsSuggest',
      _handoff(HandoffStatus.needsSuggest),
      evidence: ClosureEvidence.none,
      closure: AutomaticClosure.stayOpen,
    );
    row(
      'suggest confirmed, debug skipped and recorded: teardown as a reminder',
      _handoff(HandoffStatus.readyForDebug,
          disposition: DebugDisposition.skipped),
      evidence: ClosureEvidence.confirmedBySuggest,
      closure: AutomaticClosure.teardownAsReminder,
    );
    row(
      'suggest confirmed, nothing recorded about debug: the owner is reminded',
      _handoff(HandoffStatus.readyForDebug),
      evidence: ClosureEvidence.debugUnrecorded,
      closure: AutomaticClosure.remindOwner,
    );
    row(
      'converged with no evidence at all: no teardown, it stays open',
      SessionState.parse(blankHandoff),
      evidence: ClosureEvidence.none,
      closure: AutomaticClosure.stayOpen,
    );
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
