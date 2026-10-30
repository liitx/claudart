import 'dart:io';
import '../environment.dart';

/// ANSI escape sequences for terminal styling and cursor control.
///
/// Use [c] to apply a colour/style — it strips codes automatically when
/// stdout is not a TTY so piped output stays clean.

// ── Styles ─────────────────────────────────────────────────────────────────────
const String reset  = '\x1b[0m';
const String bold   = '\x1b[1m';
const String dim    = '\x1b[2m';

// ── Foreground colours ─────────────────────────────────────────────────────────
const String red     = '\x1b[31m';
const String green   = '\x1b[32m';
const String yellow  = '\x1b[33m';
const String magenta = '\x1b[35m';
const String cyan    = '\x1b[36m';
const String white   = '\x1b[37m';
const String grey    = '\x1b[90m';

// ── Cursor control ─────────────────────────────────────────────────────────────
const String hideCursor = '\x1b[?25l';
const String showCursor = '\x1b[?25h';

/// Move cursor up [n] lines.
String cursorUp(int n) => '\x1b[${n}A';

/// Go to start of line and clear to end.
const String clearLine = '\r\x1b[K';

// ── Helper ─────────────────────────────────────────────────────────────────────

/// Test-only override — when non-null, short-circuits every other check
/// (env vars, `stdout.hasTerminal`) so tests get deterministic output
/// regardless of the ambient shell environment. Set back to `null` to
/// restore normal detection.
bool? colorEnabledOverride;

/// Whether colour codes should be emitted. `NO_COLOR` forces off,
/// `FORCE_COLOR` / `CLAUDART_FORCE_COLOR` force on (e.g. for panels that read
/// ANSI but aren't a TTY); otherwise follow the terminal.
bool get colorEnabled {
  if (colorEnabledOverride != null) return colorEnabledOverride!;
  final env = processEnvironment;
  if (env.containsKey('NO_COLOR')) return false;
  if (env.containsKey('FORCE_COLOR') ||
      env.containsKey('CLAUDART_FORCE_COLOR')) {
    return true;
  }
  return stdout.hasTerminal;
}

/// Wraps [text] with [code] + [reset] when [colorEnabled]; returns [text]
/// unchanged otherwise so piped output and `NO_COLOR` consumers stay clean.
String c(String code, String text) => colorEnabled ? '$code$text$reset' : text;
