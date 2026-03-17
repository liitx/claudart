String handoffTemplate({
  required String branch,
  required String date,
  required String bug,
  required String expected,
  required String projectName,
  String? files,
  String? blocs,
}) {
  final filesSection = files ?? '_Not yet determined._';
  final blocsSection = blocs ?? '_Not yet determined._';

  return '''# Agent Handoff — $projectName

> Session started: $date | Branch: $branch
> Updated: $date
> Source of truth between suggest and debug agents.
> Managed by: claudart (https://github.com/liitx/claudart)

---

## Status

suggest-investigating

---

## Bug

$bug

---

## Expected Behavior

$expected

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
$filesSection

### BLoCs / providers in play
$blocsSection

### Classes / methods in play
_Not yet determined._

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
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

const String blankHandoff = '''# Agent Handoff

> Source of truth between suggest and debug agents.
> Run `claudart setup` to begin a new session.

---

## Status

suggest-investigating

---

## Bug

_Not yet determined._

---

## Expected Behavior

_Not yet determined._

---

## Root Cause

_Not yet determined._

---

## Scope

### Files in play
_Not yet determined._

### BLoCs / providers in play
_Not yet determined._

### Classes / methods in play
_Not yet determined._

### Must not touch
_Not yet determined._

---

## Constraints

_None yet._

---

## Debug Progress

### What was attempted
_Nothing yet._

### What changed (files modified)
_Nothing yet._

### What is still unresolved
_Nothing yet._

### Specific question for suggest
_Nothing yet._

---

## Suggest Resume Notes

_Nothing yet._
''';
