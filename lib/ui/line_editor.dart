import 'dart:convert';
import 'dart:io';

const _prompt = '> ';

/// Reads a line of user input with full cursor movement support:
/// left/right arrows, home/end, backspace, delete, Ctrl+A/E/U.
///
/// When stdin is not a TTY (CI, pipe) falls back to [stdin.readLineSync]
/// so behaviour is always well-defined.
///
/// Returns null when [optional] is true and the user submits empty input.
String? readLine({bool optional = false}) {
  stdout.write(_prompt);
  if (!stdin.hasTerminal) {
    final raw = stdin.readLineSync()?.trim();
    if (raw == null || raw.isEmpty) return optional ? null : readLine(optional: optional);
    return raw;
  }
  return _editLine(optional: optional);
}

// ── Editor loop ───────────────────────────────────────────────────────────────

String? _editLine({required bool optional}) {
  final buf = <String>[];
  var cursor = 0;
  var lastDrawnLength = 0;

  void redraw() {
    int termWidth;
    try {
      termWidth = stdout.terminalColumns;
    } on UnsupportedError {
      termWidth = 80;
    }
    final linesUsed = wrappedLineCount(_prompt.length, lastDrawnLength, termWidth);
    if (linesUsed > 1) stdout.write('\x1b[${linesUsed - 1}A');
    final text = buf.join();
    stdout.write('\r\x1b[J$_prompt$text');
    lastDrawnLength = buf.length;
    final tail = buf.length - cursor;
    if (tail > 0) stdout.write('\x1b[${tail}D');
  }

  stdin.echoMode = false;
  stdin.lineMode = false;

  try {
    while (true) {
      final key = _readKey();
      switch (key.type) {
        case _KeyType.char:
          buf.insert(cursor, key.char!);
          cursor++;
          redraw();

        case _KeyType.left:
          if (cursor > 0) {
            cursor--;
            redraw();
          }

        case _KeyType.right:
          if (cursor < buf.length) {
            cursor++;
            redraw();
          }

        case _KeyType.home:
          cursor = 0;
          redraw();

        case _KeyType.end:
          cursor = buf.length;
          redraw();

        case _KeyType.backspace:
          if (cursor > 0) {
            buf.removeAt(cursor - 1);
            cursor--;
            redraw();
          }

        case _KeyType.delete:
          if (cursor < buf.length) {
            buf.removeAt(cursor);
            redraw();
          }

        case _KeyType.ctrlU:
          buf.clear();
          cursor = 0;
          redraw();

        case _KeyType.enter:
          stdout.write('\n');
          final result = buf.join().trim();
          return result.isEmpty && optional ? null : result;

        case _KeyType.ctrlC:
          stdout.write('\n');
          exit(0);

        case _KeyType.other:
          break;
      }
    }
  } finally {
    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}

// ── Display ───────────────────────────────────────────────────────────────────

/// Returns the number of terminal lines occupied by [promptLen] + [bufLen]
/// characters at [termWidth] columns wide. Always returns at least 1.
///
/// Used by the [_editLine] redraw closure to know how many lines to clear
/// when input wraps across terminal width.
int wrappedLineCount(int promptLen, int bufLen, int termWidth) {
  if (termWidth <= 0) return 1;
  final total = promptLen + bufLen;
  if (total == 0) return 1;
  return ((total - 1) ~/ termWidth) + 1;
}

// ── Key reading ───────────────────────────────────────────────────────────────

enum _KeyType {
  char,
  left,
  right,
  home,
  end,
  backspace,
  delete,
  ctrlU,
  enter,
  ctrlC,
  other,
}

class _Key {
  final _KeyType type;
  final String? char;
  const _Key(this.type, [this.char]);
}

_Key _readKey() {
  final b = stdin.readByteSync();

  if (b == 10 || b == 13) return const _Key(_KeyType.enter);
  if (b == 3) return const _Key(_KeyType.ctrlC);
  if (b == 127 || b == 8) return const _Key(_KeyType.backspace);
  if (b == 21) return const _Key(_KeyType.ctrlU);
  if (b == 1) return const _Key(_KeyType.home);    // Ctrl+A
  if (b == 5) return const _Key(_KeyType.end);     // Ctrl+E

  // ESC sequence
  if (b == 27) {
    final b2 = stdin.readByteSync();
    if (b2 == 91) {
      // ESC[
      final b3 = stdin.readByteSync();
      switch (b3) {
        case 65:
          return const _Key(_KeyType.other);   // up arrow — not used in prompts
        case 66:
          return const _Key(_KeyType.other);   // down arrow
        case 67:
          return const _Key(_KeyType.right);   // →
        case 68:
          return const _Key(_KeyType.left);    // ←
        case 72:
          return const _Key(_KeyType.home);    // Home (xterm)
        case 70:
          return const _Key(_KeyType.end);     // End (xterm)
        case 51:
          stdin.readByteSync();                // ESC[3~ = Delete, consume ~
          return const _Key(_KeyType.delete);
        case 49:
          stdin.readByteSync();                // ESC[1~ = Home (vt), consume ~
          return const _Key(_KeyType.home);
        case 52:
          stdin.readByteSync();                // ESC[4~ = End (vt), consume ~
          return const _Key(_KeyType.end);
      }
    }
    return const _Key(_KeyType.other);
  }

  // Printable: ASCII (32–126) or UTF-8 multi-byte lead byte.
  if (b >= 32) {
    final charBytes = <int>[b];
    if (b >= 0xC0 && b < 0xE0) {
      charBytes.add(stdin.readByteSync()); // 2-byte UTF-8
    } else if (b >= 0xE0 && b < 0xF0) {
      charBytes.add(stdin.readByteSync()); // 3-byte UTF-8
      charBytes.add(stdin.readByteSync());
    } else if (b >= 0xF0) {
      charBytes.add(stdin.readByteSync()); // 4-byte UTF-8
      charBytes.add(stdin.readByteSync());
      charBytes.add(stdin.readByteSync());
    }
    try {
      return _Key(_KeyType.char, utf8.decode(charBytes));
    } on FormatException catch (_) {
      return const _Key(_KeyType.other);
    }
  }

  return const _Key(_KeyType.other);
}
