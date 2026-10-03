import 'dart:io';

/// Whether raw terminal input (no echo, no line buffering) can really be used.
///
/// `Stdin.hasTerminal` alone is not enough: on macOS Dart reports `true` for
/// `/dev/null` (a character device), and the very next `echoMode = false`
/// then throws `StdinException` (ENODEV, errno 19). Probing the echo mode
/// with a read is side-effect free and fails exactly when raw mode is
/// unusable, so callers can fall back to line-based input instead of crashing.
///
/// [hasTerminal] and [echoModeProbe] are injectable so this is testable
/// without a real terminal.
bool canUseRawTerminal({
  bool Function()? hasTerminal,
  void Function()? echoModeProbe,
}) {
  final has = (hasTerminal ?? () => stdin.hasTerminal)();
  if (!has) return false;
  try {
    (echoModeProbe ?? _probeEchoMode)();
    return true;
  } on StdinException {
    return false;
  }
}

void _probeEchoMode() {
  stdin.echoMode; // ignore: unnecessary_statements — the getter throws when raw mode is unusable
}
