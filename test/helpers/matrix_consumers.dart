// matrix_consumers.dart — which decision tables the code has, and who decides
// with them.
//
// A decision table is a function whose result is an enum value (or a list or
// set of them) chosen by a `switch`: what a status moves to, what an automatic
// close does, which reactions a move calls for. A table is worth its tests only
// if something decides with its result. A caller that only prints the result
// (reads its `.label`, or passes it into a message) is a display; if every
// caller of a table is a display, the table can change without any behavior
// changing, and its own tests prove nothing about what the program does. The
// existing "is the symbol consulted" check cannot see that: a display is a
// consult. This reads each caller and names which kind it is.

/// A decision table: where it is declared and what it returns.
typedef DecisionTable = ({
  String name,
  String file,
  int line,
  String returns,

  /// Declared as `get name`, so it is read as `.name` and not called.
  bool getter,
});

/// What a caller does with a decision table's result.
enum ConsumerKind {
  /// Decides something with the result: a condition, a branch, a value that
  /// goes on to change state or run a command.
  control,

  /// Only shows the result: reads its label or name, or puts it in a message.
  display,
}

/// One call of a decision table.
typedef Consumer = ({String file, int line, String text, ConsumerKind kind});

/// What a table's callers add up to.
enum TableVerdict {
  /// At least one caller decides with the result.
  drives,

  /// Callers exist and every one only displays the result.
  displayOnly,

  /// No caller outside the table's own declaration.
  unconsumed,

  /// A getter whose name another declaration shares, so a read of `.name`
  /// cannot be told from text to be a read of this table. Not counted.
  unattributed,
}

/// The accessors that turn an enum value into text for a person.
const _textAccessors = {'label', 'name'};

/// Words before a call that make everything inside it a message.
const _messageOpeners = ['print(', 'UserText.', 'stdout.write', 'writeln('];

/// Names too general to find by text.
const _unsearchable = {'of', 'parse', 'fromString', 'byName', 'values'};

/// [source] with whole-line comments emptied, not removed, so a line keeps its
/// number.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

/// Every enum named in [sources].
Set<String> enumNames(Map<String, String> sources) => {
      for (final source in sources.values)
        for (final match in RegExp(r'^enum (\w+)', multiLine: true).allMatches(source))
          match.group(1)!,
    };

/// The index of the character that closes the bracket opened at [open], skipping
/// string literals, or null when none does.
int? closingIndex(String text, int open) {
  const pairs = {'(': ')', '{': '}', '[': ']'};
  final stack = <String>[];
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (char == "'" || char == '"') {
      var j = i + 1;
      while (j < text.length && text[j] != char) {
        if (text[j] == r'\') j++;
        j++;
      }
      i = j;
    } else if (pairs.containsKey(char)) {
      stack.add(pairs[char]!);
    } else if (stack.isNotEmpty && char == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return i;
    }
  }
  return null;
}

/// The decision tables declared in [sources] whose results are in [enums].
List<DecisionTable> findDecisionTables(
  Map<String, String> sources,
  Set<String> enums,
) {
  final declaration = RegExp(
    r'^[ \t]*(?:static[ \t]+)?((?:List|Set)<(\w+)>|(\w+))\??[ \t]+(\w+)\(',
    multiLine: true,
  );
  final getterDeclaration = RegExp(
    r'^[ \t]*(?:static[ \t]+)?((?:List|Set)<(\w+)>|(\w+))\??[ \t]+get[ \t]+(\w+)[ \t]*(?==>|\{)',
    multiLine: true,
  );
  final tables = <DecisionTable>[];
  for (final entry in sources.entries) {
    final code = _withoutComments(entry.value);
    for (final match in getterDeclaration.allMatches(code)) {
      final returns = match.group(2) ?? match.group(3)!;
      if (!enums.contains(returns)) continue;
      final rest = code.substring(match.end).trimLeft();
      final bodyStart = code.length - rest.length;
      final bodyEnd = rest.startsWith('=>')
          ? _expressionEnd(code, bodyStart)
          : closingIndex(code, bodyStart);
      if (bodyEnd == null ||
          !RegExp(r'\bswitch\s*\(').hasMatch(code.substring(bodyStart, bodyEnd))) {
        continue;
      }
      tables.add((
        name: match.group(4)!,
        file: entry.key,
        line: '\n'.allMatches(code.substring(0, match.start)).length + 1,
        returns: match.group(1)!,
        getter: true,
      ));
    }
    for (final match in declaration.allMatches(code)) {
      final returns = match.group(2) ?? match.group(3)!;
      final name = match.group(4)!;
      if (!enums.contains(returns) || _unsearchable.contains(name)) continue;
      final paramsOpen = match.end - 1;
      final paramsClose = closingIndex(code, paramsOpen);
      if (paramsClose == null) continue;
      final rest = code.substring(paramsClose + 1).trimLeft();
      final bodyStart = code.length - rest.length;
      final int? bodyEnd;
      if (rest.startsWith('=>')) {
        final end = _expressionEnd(code, bodyStart);
        bodyEnd = end;
      } else if (rest.startsWith('{')) {
        bodyEnd = closingIndex(code, bodyStart);
      } else {
        continue;
      }
      if (bodyEnd == null) continue;
      if (!RegExp(r'\bswitch\s*\(').hasMatch(code.substring(bodyStart, bodyEnd))) {
        continue;
      }
      tables.add((
        name: name,
        file: entry.key,
        line: '\n'.allMatches(code.substring(0, match.start)).length + 1,
        returns: match.group(1)!,
        getter: false,
      ));
    }
  }
  return tables;
}

/// The index of the `;` that ends the expression starting at [from], outside
/// any bracket and string.
int? _expressionEnd(String text, int from) {
  var depth = 0;
  for (var i = from; i < text.length; i++) {
    final char = text[i];
    if (char == "'" || char == '"') {
      var j = i + 1;
      while (j < text.length && text[j] != char) {
        if (text[j] == r'\') j++;
        j++;
      }
      i = j;
    } else if ('({['.contains(char)) {
      depth++;
    } else if (')}]'.contains(char)) {
      depth--;
    } else if (char == ';' && depth == 0) {
      return i;
    }
  }
  return null;
}

/// What the use of a table found in [line] at [nameIndex] does with its result.
/// A getter read as `.name` is given as [getterName]; a function is called, and
/// its result ends at the closing parenthesis.
ConsumerKind classifyConsumer(String line, int nameIndex, {String? getterName}) {
  final before = line.substring(0, nameIndex);
  if (_messageOpeners.any(before.contains)) return ConsumerKind.display;
  final int? resultEnd;
  if (getterName != null) {
    resultEnd = nameIndex + 1 + getterName.length;
  } else {
    final open = line.indexOf('(', nameIndex);
    final close = open < 0 ? null : closingIndex(line, open);
    resultEnd = close == null ? null : close + 1;
  }
  if (resultEnd != null) {
    final after = RegExp(r'^\??\.(\w+)').firstMatch(line.substring(resultEnd));
    if (after != null && _textAccessors.contains(after.group(1))) {
      return ConsumerKind.display;
    }
  }
  return ConsumerKind.control;
}

/// Every call of [table] in [sources], other than its own declaration.
List<Consumer> consumersOf(DecisionTable table, Map<String, String> sources) {
  final call = table.getter
      ? RegExp('\\.${table.name}\\b')
      : RegExp('\\b${table.name}\\(');
  final found = <Consumer>[];
  for (final entry in sources.entries) {
    final original = entry.value.split('\n');
    for (var index = 0; index < original.length; index++) {
      final line = original[index];
      if (line.trimLeft().startsWith('//')) continue;
      final match = call.firstMatch(line);
      if (match == null) continue;
      if (entry.key == table.file && index + 1 == table.line) continue;
      if (RegExp('^[ \\t]*(?:static[ \\t]+)?[\\w<>?]+[ \\t]+(?:get[ \\t]+)?${table.name}\\b[ \\t]*(\\(|=>|\\{)').hasMatch(line)) {
        continue;
      }
      found.add((
        file: entry.key,
        line: index + 1,
        text: line.trim(),
        kind: classifyConsumer(
          line,
          match.start,
          getterName: table.getter ? table.name : null,
        ),
      ));
    }
  }
  return found;
}

/// Whether [table] is a getter and another getter or field of the same name is
/// declared in [sources], so its readers cannot be attributed from text.
bool isAmbiguousGetter(DecisionTable table, Map<String, String> sources) {
  if (!table.getter) return false;
  final declaration = RegExp(
    '(?:\\bget[ \\t]+|\\bfinal[ \\t]+[\\w<>?,]+[ \\t]+)${table.name}\\b',
  );
  final declared = sources.values
      .map((source) => declaration.allMatches(source).length)
      .fold<int>(0, (sum, count) => sum + count);
  return declared > 1;
}

/// What [consumers] add up to; [ambiguous] when [isAmbiguousGetter] says the
/// readers cannot be attributed.
TableVerdict verdictOf(List<Consumer> consumers, {bool ambiguous = false}) {
  if (ambiguous) return TableVerdict.unattributed;
  if (consumers.isEmpty) return TableVerdict.unconsumed;
  return consumers.any((c) => c.kind == ConsumerKind.control)
      ? TableVerdict.drives
      : TableVerdict.displayOnly;
}
