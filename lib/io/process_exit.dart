// process_exit.dart — the one way a command leaves the process
//
// A command that is done, or cannot go on, leaves through [exitProcess], never
// through `dart:io`'s `exit` itself. That is what lets the boundary that runs
// a command (`runRecorded`) record how it ended before the process goes: a
// bare `exit` unwinds nothing, so whatever is not written by then is lost.

import 'dart:io' as io;

void Function(int code)? _beforeExit;
Never Function(int code)? _leave;

/// Leaves the process with [code], after the hook of the run in progress, if
/// there is one, has heard it.
Never exitProcess(int code) => exitProcessWith(code);

/// [exitProcess] with the way of leaving given, for a test that must not end
/// its own process.
Never exitProcessWith(int code, {Never Function(int code)? leave}) {
  _beforeExit?.call(code);
  (leave ?? _leave ?? io.exit)(code);
}

/// Runs [body] with [beforeExit] hearing every [exitProcess] inside it, and
/// [leave] as the way out when given. Both are removed when [body] ends.
Future<T> withExitHook<T>({
  required void Function(int code) beforeExit,
  required Future<T> Function() body,
  Never Function(int code)? leave,
}) async {
  _beforeExit = beforeExit;
  _leave = leave;
  try {
    return await body();
  } finally {
    _beforeExit = null;
    _leave = null;
  }
}
