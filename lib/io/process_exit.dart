// process_exit.dart — the one way a command leaves the process
//
// A command that is done, or cannot go on, leaves through [exitProcess], never
// through `dart:io`'s `exit` itself. That is what lets the boundary that runs
// a command (`runRecorded`) record how it ended before the process goes: a
// bare `exit` unwinds nothing, so whatever is not written by then is lost.

import 'dart:io' as io;

void Function(int code, String? reason)? _beforeExit;
Never Function(int code)? _leave;
String? _exitReason;

/// Names why the command is about to leave, for the record of the run: the
/// code that decides to exit says so just before it does. An exit that names
/// none leaves the record without a reason, so a missing reason is visible.
void noteExitReason(Enum reason) => _exitReason = reason.name;

/// Leaves the process with [code], after the hook of the run in progress, if
/// there is one, has heard it.
Never exitProcess(int code) => exitProcessWith(code);

/// [exitProcess] with the way of leaving given, for a test that must not end
/// its own process.
Never exitProcessWith(int code, {Never Function(int code)? leave}) {
  _beforeExit?.call(code, _exitReason);
  (leave ?? _leave ?? io.exit)(code);
}

/// Runs [body] with [beforeExit] hearing every [exitProcess] inside it, with
/// the reason the exit named, and [leave] as the way out when given. Both, and
/// any reason named, are removed when [body] ends.
Future<T> withExitHook<T>({
  required void Function(int code, String? reason) beforeExit,
  required Future<T> Function() body,
  Never Function(int code)? leave,
}) async {
  _beforeExit = beforeExit;
  _leave = leave;
  _exitReason = null;
  try {
    return await body();
  } finally {
    _beforeExit = null;
    _leave = null;
    _exitReason = null;
  }
}
