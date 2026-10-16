# Research: accounting for hangs and unexpected output, and deriving expected values from variants (2026-10-12)

Owner ask: use thresholds, a listener, or recorded-correct output to determine what is expected; make mocks model state
(not strings); put a getter on each variant with a reusable function that reads it, to serve as the expected value and to
create topology. Every Dart claim below was run, not recalled (throwaway package /tmp/exp, `test` ^1.31).

## 1. Verified facts (Dart `test` package)

| Question | Result |
|---|---|
| Do records of enums compare structurally in `expect(..., equals(...))`? | Yes. `[(S.a, 1)]` equals `[(S.a, 1)]` and differs from `[(S.b, 1)]`. Transition logs can be expected as record lists, not strings. |
| Can a typed stream be asserted as a listener would see it? | Yes. `expectLater(stream, emitsInOrder([S.a, S.b, emitsDone]))` and `neverEmits(S.b)` work. No extra dependency. |
| Does a per-test threshold catch an async hang? | Yes. `timeout: Timeout(Duration(seconds: 1))` failed an unresolved `Completer` future with `TimeoutException ... Test timed out after 1 seconds` at 1 s. |
| Does a threshold catch a BLOCKING synchronous read (`stdin.readLineSync()`)? | **No.** With stdin held open, a 1 s `timeout:` did not fire in 25 s. A synchronous block freezes the isolate, so the timer cannot run. |
| What does `readLineSync()` do at EOF? | Returns `null` immediately, so the test finishes instead of hanging. |

Consequence: thresholds and listeners are the right tools for async flows (pipeline events, mutation runner events, future
state stream). They cannot defend against a synchronous prompt. That needs the seam to be unreachable or stdin at EOF.

## 2. What the hang actually was (reproduced)

Inverting the debug gate made tests that never scripted `confirmFn` fall through to the real stdin prompt and hang for
minutes. Fixed in two layers, both verified:
1. `test/helpers/unscripted.dart` (`unscriptedConfirm/Prompt/Pick`) passed to every `runSuggest`/`runDebug` call that did
   not script a seam. Reproduced the inverted gate with stdin held open: now fails in 3 s with
   `unscripted confirm: "Run debug anyway?"`.
2. `make test` and `.githooks/pre-push` run `dart test ... < /dev/null`. Full suite passes (1626 tests) at EOF.

## 3. Expected values from the variant's own getter

Reusable function (`test/helpers/variant_topology.dart`):
- `topologyOf<V extends Enum, T>(variants, T Function(V) getter)` -> `Map<V, T>`: the variant's own answer.
- `renderTopology<V>(variants, {'getterName': getter, ...})` -> markdown variant x getter table (the matrix visualized).

Used by the consumer matrices (`runDebug` gate, `checkHandoffStatus`): expected comes from `canStartDebug`, not a hand-typed set.

**Limit, learned the hard way this session:** a consumer test derived from a getter proves the consumer FOLLOWS the getter,
not that the getter is RIGHT. Earlier in this session a test derived expected from the same getter it was testing and
could not fail. So two layers are required: (a) one independent literal table per enum (the contract; see the wire-value
table in `session_state_test.dart`), (b) consumer tests derived from the getter (so adding a variant updates them for free).

Topology of `HandoffStatus` generated from code:

| variant | value | isPersisted | canStartDebug | expectsSuggest | expectsDebug |
|---|---|---|---|---|---|
| suggestInvestigating | suggest-investigating | true | false | true | false |
| readyForSuggest | ready-for-suggest | true | false | true | false |
| readyForDebug | ready-for-debug | true | true | false | true |
| debugInProgress | debug-in-progress | true | true | false | true |
| debugComplete | debug-complete | true | false | false | false |
| needsSuggest | needs-suggest | true | false | true | false |
| noHandoff | no-handoff | false | false | true | false |
| unknown | unknown | false | false | true | false |

What the table already shows: the `expectsDebug` and `canStartDebug` columns are identical. Same concept defined twice
(and `expectsDebug`/`expectsSuggest` have no lib callers, ledger A6). Candidate: define one, delete or alias the other;
`HandoffStatus` is exported to zedup, so confirm zedup's use first. Not changed in this task.

## 4. Recording "correct" output as the expectation (not built)

- Do not golden-file strings. Record TYPED facts: a list of `(from, event, to)` records, or `MutationEvent`/`PipelineEvent`
  values, from a run a human judged correct, and assert later runs with `equals` on the records.
- Needs a source of events: the typed transition function plus `Stream<HandoffTransition>` (plan slice 2). The mutation
  runner (`tool/mutation/`, branch `feat/mutation-runner-streams`) already is this pattern: events in, `emitsInOrder` out.
- Threshold use: assert counts and ordering, plus a per-test timeout for async flows; use `package:fake_async` only if
  virtual time is needed (not a direct dependency today, check `pubspec.lock` before adding).

## 5. Mocks that model state (proposal, not built)

- Replace substring-matching `MockClaudeRunner.responses` (falls back to the first response silently) with a scripted
  fake keyed by a typed step id; an unscripted call throws (same principle as `unscripted*`), and every call is recorded as a
  typed record the test asserts.
- Prefer fakes (`MemoryFileIO`) for state, mocktail `Mock` only for call verification.
- A mock driven from the variant getters: the fake's script is `topologyOf(AgentFlow.values, (f) => f.<getter>)`, so adding
  a variant forces the mock to answer for it or fail loudly.

## 6. Next small tasks (dependency order)

1. Typed transition function + `HandoffEvent` (the source of recordable transitions).
2. `Stream<HandoffTransition>` and one listener-based test per flow using `emitsInOrder`.
3. Scripted typed fake for `MockClaudeRunner` (unscripted call throws).
4. Resolve `expectsDebug` vs `canStartDebug` overlap; generate this topology table into docs and check it for staleness
   with the `stateOf` render-and-diff pattern.
