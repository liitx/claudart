import 'session_state.dart';
import '../teardown_utils.dart';

/// Severity of a sync issue found during preflight.
enum IssueSeverity { warning, error }

/// The claudart operation a preflight check is guarding.
enum ClaudartOperation {
  debug,
  save,
  test;

  static ClaudartOperation fromString(String s) => switch (s) {
        'debug' => debug,
        'save' => save,
        _ => test,
      };
}

/// A single issue found during a preflight sync check.
class SyncIssue {
  final IssueSeverity severity;
  final String message;
  final String? suggestion;

  const SyncIssue(this.severity, this.message, {this.suggestion});

  @override
  String toString() {
    final tag = severity == IssueSeverity.error ? '✗' : '⚠';
    final hint = suggestion != null ? '\n  → $suggestion' : '';
    return '$tag $message$hint';
  }
}

/// Aggregated result of one or more preflight checks.
class SyncCheckResult {
  final List<SyncIssue> issues;

  const SyncCheckResult(this.issues);

  factory SyncCheckResult.clean() => const SyncCheckResult([]);

  bool get isClean => issues.isEmpty;
  bool get hasErrors => issues.any((i) => i.severity == IssueSeverity.error);
  bool get hasWarnings =>
      issues.any((i) => i.severity == IssueSeverity.warning);

  /// Merges two results into one.
  SyncCheckResult merge(SyncCheckResult other) =>
      SyncCheckResult([...issues, ...other.issues]);

  @override
  String toString() => issues.map((i) => i.toString()).join('\n');
}

// ── Check 1: Skills.md pending vs handoff root cause ─────────────────────────

/// Checks whether skills.md pending section reflects the confirmed root cause
/// in the handoff.
///
/// Returns a warning when root cause is confirmed in the handoff but no
/// matching pending entry exists — meaning `claudart save` has not been run
/// since the root cause was confirmed.
SyncCheckResult checkSkillsSync(
  String handoffContent,
  String skillsContent,
) {
  final state = SessionState.parse(handoffContent);

  if (!state.hasActiveContent) return SyncCheckResult.clean();

  final rootCauseConfirmed = !_isBlank(state.rootCause);
  if (!rootCauseConfirmed) return SyncCheckResult.clean();

  final pendingHasEntry = _pendingHasBranch(skillsContent, state.branch);
  if (pendingHasEntry) return SyncCheckResult.clean();

  return const SyncCheckResult([
    SyncIssue(
      IssueSeverity.warning,
      'Root cause confirmed in handoff but not checkpointed in skills.md.',
      suggestion: 'Run `claudart save` to sync before continuing.',
    ),
  ]);
}

bool _pendingHasBranch(String skillsContent, String branch) {
  if (skillsContent.isEmpty) return false;
  final pending = extractSection(skillsContent, 'Pending');
  if (pending.isEmpty) return false;
  return pending.contains('`$branch`');
}

// ── Check 2: Current git branch vs handoff branch ────────────────────────────

/// Checks whether the current git branch matches the branch recorded in the
/// handoff.
///
/// Returns a warning when [currentBranch] is known (non-null) and does not
/// match the handoff branch. Null [currentBranch] means git context was not
/// available (e.g. in tests) — no check is performed.
SyncCheckResult checkBranchSync(String handoffContent, String? currentBranch) {
  if (currentBranch == null) return SyncCheckResult.clean();
  final state = SessionState.parse(handoffContent);
  if (!state.hasActiveContent) return SyncCheckResult.clean();
  if (state.branch == 'unknown') return SyncCheckResult.clean();
  if (state.branch == currentBranch) return SyncCheckResult.clean();

  return SyncCheckResult([
    SyncIssue(
      IssueSeverity.warning,
      'Current branch "$currentBranch" does not match handoff branch "${state.branch}".',
      suggestion:
          'Switch back to "${state.branch}" or run `claudart setup` to start a new session on this branch.',
    ),
  ]);
}

// ── Check 3: Handoff status for intended operation ────────────────────────────

/// Checks whether the handoff status is appropriate for [operation].
SyncCheckResult checkHandoffStatus(
    ClaudartOperation operation, String handoffContent) {
  final state = SessionState.parse(handoffContent);

  return switch (operation) {
    ClaudartOperation.debug
        when state.status != HandoffStatus.readyForDebug &&
            state.status != HandoffStatus.debugInProgress =>
      SyncCheckResult([
        SyncIssue(
          IssueSeverity.error,
          'Handoff status is "${state.status.value}" — debug requires ready-for-debug.',
          suggestion:
              'Complete /suggest first, then run /save to lock the root cause.',
        ),
      ]),
    ClaudartOperation.save when !state.hasActiveContent =>
      const SyncCheckResult([
        SyncIssue(
          IssueSeverity.warning,
          'No active session content to checkpoint.',
          suggestion: 'Run `claudart setup` to start a session first.',
        ),
      ]),
    _ => SyncCheckResult.clean(),
  };
}

// ── Check 3: Coverage map gaps in a test_X.md file ───────────────────────────

/// Scans [testFileContent] for coverage table rows marked `—` (gap).
///
/// Returns the scenario names of any uncovered rows. An empty list means
/// the coverage map has no declared gaps.
List<String> checkCoverageGaps(String testFileContent) {
  final gaps = <String>[];
  for (final line in testFileContent.split('\n')) {
    // Match markdown table rows ending with | — | or | —    |
    if (!RegExp(r'\|\s*—\s*\|?\s*$').hasMatch(line)) continue;
    final cols = line
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (cols.isNotEmpty) gaps.add(cols.first);
  }
  return gaps;
}

// ── Combined preflight ────────────────────────────────────────────────────────

/// Runs all three preflight checks and returns the merged result.
///
/// [operation] guards which workflow step is about to run.
/// [testFileContents] is an optional map of filename → content for coverage
/// gap checks (only used when [operation] is [ClaudartOperation.test]).
SyncCheckResult runPreflight({
  required ClaudartOperation operation,
  required String handoffContent,
  String skillsContent = '',
  Map<String, String> testFileContents = const {},
  String? currentBranch,
}) {
  var result = SyncCheckResult.clean();

  result = result.merge(checkHandoffStatus(operation, handoffContent));
  result = result.merge(checkSkillsSync(handoffContent, skillsContent));
  result = result.merge(checkBranchSync(handoffContent, currentBranch));

  if (operation == ClaudartOperation.test) {
    for (final entry in testFileContents.entries) {
      final gaps = checkCoverageGaps(entry.value);
      if (gaps.isNotEmpty) {
        result = result.merge(SyncCheckResult([
          SyncIssue(
            IssueSeverity.warning,
            '${entry.key}: ${gaps.length} coverage gap(s): ${gaps.join(', ')}',
            suggestion: 'Fill gaps or mark as intentional before committing.',
          ),
        ]));
      }
    }
  }

  return result;
}

bool _isBlank(String s) =>
    s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');
