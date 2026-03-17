import 'dart:io';

/// ANSI escape sequences for terminal styling and cursor control.
///
/// Use [c] to apply a colour/style — it strips codes automatically when
/// stdout is not a TTY so piped output stays clean.

// ── Styles ─────────────────────────────────────────────────────────────────────
const String reset  = '\x1b[0m';
const String bold   = '\x1b[1m';
const String dim    = '\x1b[2m';

// ── Foreground colours ─────────────────────────────────────────────────────────
const String red    = '\x1b[31m';
const String green  = '\x1b[32m';
const String yellow = '\x1b[33m';
const String cyan   = '\x1b[36m';

// ── Cursor control ─────────────────────────────────────────────────────────────
const String hideCursor = '\x1b[?25l';
const String showCursor = '\x1b[?25h';

/// Move cursor up [n] lines.
String cursorUp(int n) => '\x1b[${n}A';

/// Go to start of line and clear to end.
const String clearLine = '\r\x1b[K';

// ── Helper ─────────────────────────────────────────────────────────────────────

/// Wraps [text] with [code] + [reset]. Returns [text] unchanged when stdout
/// is not a TTY so output piped to a file stays clean.
String c(String code, String text) =>
    stdout.hasTerminal ? '$code$text$reset' : text;
