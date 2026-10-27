import '../session/handoff_placeholder.dart';
import '../session/session_state.dart' show HandoffStatus;

String handoffTemplate({
  required String branch,
  required String date,
  required String bug,
  required String expected,
  required String projectName,
  String? files,
  String? entryPoints,
  List<String>? pendingIssues,
}) {
  final filesSection = files ?? notYetDeterminedText;
  final entryPointsSection = entryPoints ?? notYetDeterminedText;
  final pendingSection = (pendingIssues != null && pendingIssues.isNotEmpty)
      ? pendingIssues.map((i) => '- [ ] $i').join('\n')
      : '_None recorded yet._';

  return '''# Agent Handoff — $projectName

> Session started: $date | Branch: $branch
> Updated: $date
> Source of truth between suggest and debug agents.
> Managed by: claudart (https://github.com/liitx/claudart)

---

## Status

${HandoffStatus.suggestInvestigating.value}

---

## Bug

$bug

---

## Expected Behavior

$expected

---

## Root Cause

$notYetDeterminedText

---

## Scope

### Files in play
$filesSection

### Key entry points in play
$entryPointsSection

### Classes / methods in play
$notYetDeterminedText

### Must not touch
$notYetDeterminedText

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
$nothingYetText

### What changed (files modified)
$nothingYetText

### What is still unresolved
$nothingYetText

### Specific question for suggest
$nothingYetText

---

## Suggest Resume Notes

$nothingYetText

---

## Pending Issues

> Other issues found during this session, not yet the active focus.
> claudart rotate will seed the next handoff from the first unchecked item.

$pendingSection
''';
}

/// Updates (or inserts) the `> Updated: …` line in an existing handoff.
///
/// Operates on the raw string — no full parse required. Safe to call on any
/// handoff regardless of age or format.
String stampHandoffUpdated(String handoff) {
  final ts = DateTime.now().toIso8601String().split('.').first;
  final updatedLine = '> Updated: $ts';
  final pattern = RegExp(r'^> Updated: .+$', multiLine: true);
  if (pattern.hasMatch(handoff)) {
    return handoff.replaceFirst(pattern, updatedLine);
  }
  // Insert after the first `> Session started:` line if present.
  final startedPattern = RegExp(r'^(> Session started: .+)$', multiLine: true);
  final match = startedPattern.firstMatch(handoff);
  if (match != null) {
    return handoff.replaceFirst(
      match.group(0)!,
      '${match.group(0)}\n$updatedLine',
    );
  }
  // Fallback: prepend to the first `>` block.
  return handoff.replaceFirst(RegExp(r'^(> )', multiLine: true), '$updatedLine\n> ');
}

final String blankHandoff = '''# Agent Handoff

> Source of truth between suggest and debug agents.
> Run `claudart setup` to begin a new session.

---

## Status

${HandoffStatus.suggestInvestigating.value}

---

## Bug

$notYetDeterminedText

---

## Expected Behavior

$notYetDeterminedText

---

## Root Cause

$notYetDeterminedText

---

## Scope

### Files in play
$notYetDeterminedText

### Key entry points in play
$notYetDeterminedText

### Classes / methods in play
$notYetDeterminedText

### Must not touch
$notYetDeterminedText

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
$nothingYetText

### What changed (files modified)
$nothingYetText

### What is still unresolved
$nothingYetText

### Specific question for suggest
$nothingYetText

---

## Suggest Resume Notes

$nothingYetText

---

## Pending Issues

> Other issues found during this session, not yet the active focus.
> claudart rotate will seed the next handoff from the first unchecked item.

_None recorded yet._
''';
