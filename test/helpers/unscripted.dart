// unscripted.dart — interaction seams that refuse to answer.
//
// runSuggest/runDebug take confirmFn/promptFn/pickFn so tests never touch a
// terminal. A test that omits a seam silently falls back to the real,
// blocking, synchronous stdin read — which the test timeout CANNOT interrupt
// (verified: a 1 s `timeout:` did not fire during a held-open stdin read), so
// a regression that reaches an unscripted interaction hangs the whole run
// instead of failing. Passing these makes the same regression fail at once,
// naming the question that was never scripted.

Never _unscripted(String kind, String detail) =>
    throw StateError('unscripted $kind: $detail — script it in the test or fix the code path that reached it');

bool unscriptedConfirm(String question) => _unscripted('confirm', '"$question"');

String? unscriptedPrompt(String question, {bool optional = false}) => _unscripted('prompt', '"$question"');

int unscriptedPick(List<String> items) => _unscripted('pick', items.join(' | '));
