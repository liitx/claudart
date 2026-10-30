// generate_user_text.dart — turns text/user_text.json into the Dart enum the
// commands read their words from.
//
//   dart run tool/generate_user_text.dart        (writes lib/generated/user_text.g.dart)
//
// The compiled CLI cannot read a file that sits beside the package, so the
// text is generated into Dart: one enum variant per key, which makes a missing
// key a compile error. `test/generated/user_text_test.dart` fails when the
// generated file and the JSON disagree.

import 'dart:convert';
import 'dart:io';

const _sourcePath = 'text/user_text.json';
const _outputPath = 'lib/generated/user_text.g.dart';

/// The generated Dart for [json]: an object of `key: text` pairs.
String generateUserText(String json) {
  final entries = (jsonDecode(json) as Map<String, dynamic>).entries.toList();
  final variants = [
    for (final entry in entries)
      "  ${entry.key}(${_literal(entry.value as String)})",
  ].join(',\n');
  return '''// GENERATED — DO NOT EDIT.
// Source: $_sourcePath. Regenerate with `dart run tool/generate_user_text.dart`.

/// Every sentence a command shows the user. A `{name}` in the text is filled
/// by [format].
enum UserText {
$variants;

  const UserText(this.template);

  /// The text with its `{name}` placeholders still in it.
  final String template;

  /// The text with each `{name}` replaced by the matching entry of [values].
  String format([Map<String, Object?> values = const {}]) =>
      template.replaceAllMapped(
        RegExp(r'\\{(\\w+)\\}'),
        (match) => values.containsKey(match[1])
            ? '\${values[match[1]]}'
            : match[0]!,
      );
}
''';
}

String _literal(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

void main() {
  File(_outputPath)
      .writeAsStringSync(generateUserText(File(_sourcePath).readAsStringSync()));
}
