// changed_lines.dart — which lines of which files a change touched
//
// Reads `git diff -U0` output and gives, for each changed file, the ranges of
// its new lines that were added or changed. A line only deleted has no new line
// and no range. Used to seed mutants on the lines a development touched, so each
// one is asked "does a test fail if this is wrong?" when it is written.

/// An inclusive range of 1-based line numbers.
typedef LineRange = ({int first, int last});

final _fileHeader = RegExp(r'^\+\+\+ b/(.+)$');
final _hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');

/// The changed line ranges of each file in [diff].
Map<String, List<LineRange>> parseChangedLines(String diff) {
  final changed = <String, List<LineRange>>{};
  String? file;
  for (final line in diff.split('\n')) {
    final header = _fileHeader.firstMatch(line);
    if (header != null) {
      file = header.group(1);
      continue;
    }
    final hunk = _hunkHeader.firstMatch(line);
    if (hunk == null || file == null) continue;
    final first = int.parse(hunk.group(1)!);
    final count = int.parse(hunk.group(2) ?? '1');
    if (count == 0) continue;
    (changed[file] ??= []).add((first: first, last: first + count - 1));
  }
  return changed;
}

/// Whether [line] is inside one of [ranges].
bool isChanged(List<LineRange> ranges, int line) =>
    ranges.any((range) => line >= range.first && line <= range.last);
