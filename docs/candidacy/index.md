# Candidate index

Generated from `docs/candidacy/ledger.jsonl` by `dart run tool/candidacy/index.dart`; a test fails when it differs. Confidence is under the initial weights, which are an assumption.

## By status

- candidate: none
- underTest: none
- proven: R1b, R3b
- bounded: R1, R2
- refuted: T7, R3
- axiom: none

Flagged (confidence stalled or dropped): none

## T7: refuted

- Statement: Stated: for every ClosureEvidence value, what teardown --headless does equals automaticClosureFor(evidence).
- Spec: docs/methodical_refactor.md :: T7
- Mocks: closure-evidence-fixtures-2026-11-13
- Variants covered: 3 of 4
- Boundary: holds for verified and confirmedBySuggest; fails for debugUnrecorded and none
- Confidence: none
- History: candidate -> underTest -> refuted
- Evidence:
  - lib/commands/teardown.dart :: evidence == ClosureEvidence.verified
  - lib/session/closure_evidence.dart :: ClosureEvidence.debugUnrecorded => AutomaticClosure.remindOwner
  - lib/session/closure_evidence.dart :: ClosureEvidence.none => AutomaticClosure.stayOpen
  - test/commands/teardown_test.dart :: a fix applied and analyzed, never verified

## R1: bounded

- Statement: Stated: for every log the README gives a cap, at any volume of lines already written and after any number of writes, the log holds exactly what the trim rule says (at most cap + 50 lines for a jsonl log, at most the cap for errors.jsonl), keeps the newest rows, and keeps them in order.
- Spec: README.md :: Each workspace keeps its own logs under `logs/`
- Mocks: log-volume-matrix-2026-11-16
- Variants covered: 7 of 8
- Boundary: holds for interactions, transitions, errors, models, steps, gates and proofs up to 10x cap lines in one write and 160 writes from the cap; performance.md has no writer; concurrency tested only at small volume
- Confidence: 0.77
- History: candidate -> underTest -> bounded
- Evidence:
  - README.md :: Each workspace keeps its own logs under `logs/`
  - test/logging/logger_test.dart :: keeps its newest $cap lines
  - test/logging/logger_test.dart :: rotation: errors keeps its newest 200 distinct errors
  - lib/logging/logger.dart :: const int _trimSlackLines = 50;
  - lib/logging/logger.dart :: if (lines.length <= maxLines + _trimSlackLines) return;
  - lib/logging/logger.dart :: lines.sublist(lines.length - maxLines).join
  - lib/logging/logger.dart :: if (trimmed.length > maxLines) {
  - lib/logging/logger.dart :: const int _maxErrors = 200;
  - lib/logging/logger.dart :: const int _maxStepRecords = 2000;

## R1b: proven

- Statement: Stated again under the corrected spec: R1 was bounded because the README listed `performance.md`, a log removed on 2026-11-06 (S9). With those rows removed the spec names seven logs. For each, at any volume and number of writes, the log holds what the trim rule says. Supersedes R1: a bounded candidate cannot move, so the corrected spec is a new candidate.
- Spec: README.md :: Each workspace keeps its own logs under `logs/`
- Mocks: log-volume-matrix-2026-11-16
- Variants covered: 7 of 7
- Boundary: holds for interactions, transitions, errors, models, steps, gates and proofs up to 10x cap lines in one write and 160 writes from the cap; concurrency tested only at small volume
- Confidence: 0.84
- History: candidate -> underTest -> proven
- Evidence:
  - README.md :: Each workspace keeps its own logs under `logs/`
  - test/logging/logger_test.dart :: keeps its newest $cap lines
  - test/logging/logger_test.dart :: rotation: errors keeps its newest 200 distinct errors
  - lib/logging/logger.dart :: const int _trimSlackLines = 50;
  - lib/logging/logger.dart :: if (lines.length <= maxLines + _trimSlackLines) return;
  - lib/logging/logger.dart :: lines.sublist(lines.length - maxLines).join
  - lib/logging/logger.dart :: if (trimmed.length > maxLines) {
  - lib/logging/logger.dart :: const int _maxErrors = 200;
  - lib/logging/logger.dart :: const int _maxStepRecords = 2000;

## R2: bounded

- Statement: Stated: every claudart log is either read for timing by a TimedSource or holds no field that reads like a duration; every row a source owns reads back as one record with the label and duration its real writer wrote, or as a gap with a named reason, never as zero and never dropped.
- Spec: docs/templates/timed_source.md :: Why this exists (spec before code)
- Mocks: timed-source-writers-2026-11-16
- Variants covered: 8 of 8
- Boundary: holds for whole-millisecond durations in interactions run rows, gates, steps and proofs; scanDuration (fractional, no unit) is not read; no volume stress; the installed binary was not run
- Confidence: 0.86
- History: candidate -> underTest -> bounded
- Evidence:
  - docs/templates/timed_source.md :: Why this exists (spec before code)
  - test/logging/timed_source_test.dart :: reads the row its writer wrote as one record
  - test/logging/timed_source_test.dart :: exactly one of read for timing or stated untimed
  - test/logging/timed_source_test.dart :: writes no field that reads like a duration
  - test/commands/status_test.dart :: timing from the logs
  - lib/logging/timed_source.dart :: if (duration < 0) return TimingGapReason.durationNegative;
  - lib/logging/timed_source.dart :: TimedSource.commandRun => LogFile.interactions,
  - lib/logging/timed_source.dart :: TimedSource.proofFault => LogFile.proofs,

## R3: refuted

- Statement: Stated: a command's run row (rowKind run, with durationMs) lands in the logs directory of the workspace the command ran in, so claudart status can show it.
- Spec: README.md :: Each workspace keeps its own logs under `logs/`
- Mocks: real-binary-status-runs-2026-11-16
- Variants covered: 1 of 1
- Boundary: holds in the seeded status tests; fails in the real binary for status
- Confidence: none
- History: candidate -> underTest -> refuted
- Evidence:
  - README.md :: Each workspace keeps its own logs under `logs/`
  - docs/methodical_refactor.md :: runRowGoesToTheGlobalLog
  - test/commands/support/project_logger_test.dart :: has no logger of its own that ignores the project

## R3b: proven

- Statement: Re-stated after R3 was refuted: a command's run row lands in the logs directory of the project it ran in (the global logs only when no project is registered; the strictest protection when the registry cannot be read), so claudart status can show it.
- Spec: README.md :: Each workspace keeps its own logs under `logs/`
- Mocks: real-binary-status-runs-2026-11-16
- Variants covered: 1 of 1
- Boundary: holds for `status` run through the Dart entry point and for every command through the CLI fixtures that read the workspace log; the compiled binary was not run
- Confidence: 0.88
- History: candidate -> underTest -> proven
- Evidence:
  - README.md :: Each workspace keeps its own logs under `logs/`
  - lib/commands/support/project_logger.dart :: final root = projectRoot ?? detectGitContext(runner: runner)?.root;
  - lib/commands/support/project_logger.dart :: if (root == null) return SessionLogger.plain(io: fileIO);
  - lib/commands/support/project_logger.dart :: return SessionLogger.labelOnly(io: fileIO);
  - lib/commands/support/project_logger.dart :: : SessionLogger.forEntry(entry, io: fileIO);
  - test/commands/support/project_logger_test.dart :: records go to its workspace logs
  - test/commands/workspaces_cli_test.dart :: --project records the targeting in the named workspace only
