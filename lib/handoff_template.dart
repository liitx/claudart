String handoffTemplate({
  required String branch,
  required String date,
  required String bug,
  required String expected,
  String? files,
  String? blocs,
}) {
  final filesSection = files ?? '_Not yet determined._';
  final blocsSection = blocs ?? '_Not yet determined._';

  return '''# Agent Handoff — dc-flutter / media_ivi

> Session started: $date | Branch: $branch
> Source of truth between suggest and debug agents.
> Managed by: claudart (https://github.com/liitx/claudart_cli)

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

const String blankHandoff = '''# Agent Handoff — dc-flutter / media_ivi

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
