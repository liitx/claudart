import 'dart:io';
import 'ansi.dart' as ansi;

/// Shows an arrow-key navigable menu and returns the **0-based** index of the
/// selected item.
///
/// Items may contain ANSI codes — the menu renderer applies selection styling
/// on top of them. When stdin is not a TTY (CI, pipe) falls back to a
/// numbered prompt so behaviour is always well-defined.
int arrowMenu(List<String> items, {int startIndex = 0}) {
  assert(items.isNotEmpty, 'arrowMenu requires at least one item');
  assert(startIndex >= 0 && startIndex < items.length);
  if (!stdin.hasTerminal) return _numberedFallback(items);
  return _arrowSelect(items, startIndex: startIndex);
}

// ── Arrow-key implementation ───────────────────────────────────────────────────

int _arrowSelect(List<String> items, {int startIndex = 0}) {
  var selected = startIndex;
  stdout.write(ansi.hideCursor);
  stdin.echoMode = false;
  stdin.lineMode = false;

  try {
    _renderMenu(items, selected);
    while (true) {
      final key = _readKey();
      switch (key) {
        case _Key.up:
          if (selected > 0) {
            selected--;
            _rerenderMenu(items, selected);
          }
        case _Key.down:
          if (selected < items.length - 1) {
            selected++;
            _rerenderMenu(items, selected);
          }
        case _Key.enter:
          _clearMenu(items.length);
          return selected;
        case _Key.ctrlC:
          _clearMenu(items.length);
          stdout.write(ansi.showCursor);
          exit(0);
        case _Key.other:
          break;
      }
    }
  } finally {
    stdout.write(ansi.showCursor);
    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}

// ── Rendering ─────────────────────────────────────────────────────────────────

// Lines below the item rows: 1 blank + 1 hint.
const int _extraLines = 2;

void _renderMenu(List<String> items, int selected) {
  for (var i = 0; i < items.length; i++) {
    _writeItem(items[i], selected: i == selected);
  }
  stdout.write('\n');
  stdout.write('  ${ansi.dim}↑↓ navigate   enter select${ansi.reset}\n');
}

void _rerenderMenu(List<String> items, int selected) {
  stdout.write(ansi.cursorUp(items.length + _extraLines));
  for (var i = 0; i < items.length; i++) {
    stdout.write(ansi.clearLine);
    _writeItem(items[i], selected: i == selected);
  }
  stdout.write('${ansi.clearLine}\n');
  stdout.write('${ansi.clearLine}  ${ansi.dim}↑↓ navigate   enter select${ansi.reset}\n');
}

void _clearMenu(int itemCount) {
  final total = itemCount + _extraLines;
  stdout.write(ansi.cursorUp(total));
  for (var i = 0; i < total; i++) {
    stdout.write('${ansi.clearLine}\n');
  }
  stdout.write(ansi.cursorUp(total));
}

void _writeItem(String item, {required bool selected}) {
  if (selected) {
    stdout.write('  ${ansi.green}${ansi.bold}▶  $item${ansi.reset}\n');
  } else {
    stdout.write('     $item\n');
  }
}

// ── Key reading ───────────────────────────────────────────────────────────────

enum _Key { up, down, enter, ctrlC, other }

_Key _readKey() {
  final b = stdin.readByteSync();
  if (b == 3) return _Key.ctrlC;
  if (b == 10 || b == 13) return _Key.enter;
  if (b == 27) {
    final b2 = stdin.readByteSync();
    if (b2 == 91) {
      final b3 = stdin.readByteSync();
      if (b3 == 65) return _Key.up;
      if (b3 == 66) return _Key.down;
    }
  }
  return _Key.other;
}

// ── Non-TTY fallback ──────────────────────────────────────────────────────────

int _numberedFallback(List<String> items) {
  for (var i = 0; i < items.length; i++) {
    stdout.writeln('  ${i + 1}. ${items[i]}');
  }
  stdout.writeln();
  while (true) {
    stdout.write('Select (1–${items.length}) > ');
    final raw = stdin.readLineSync();
    if (raw == null) return 0;  // EOF — non-interactive, default to first item
    final input = raw.trim();
    final n = int.tryParse(input);
    if (n != null && n >= 1 && n <= items.length) return n - 1;
    stdout.writeln('Enter a number between 1 and ${items.length}.');
  }
}
