import 'dart:convert';

import 'package:claudart/config/paths.dart';

import 'mocks.dart';
import 'package:claudart/logging/log_file.dart';

/// The handoff moves a command logged to `<workspace>/logs/transitions.jsonl`,
/// minus the timestamp, so a test can compare them to exact typed values.
List<Map<String, dynamic>> loggedMoves(MemoryFileIO io, String workspace) {
  final raw = io.read(logFilePath(logsDirFor(workspace), LogFile.transitions));
  return [
    for (final line in raw.split('\n').where((l) => l.isNotEmpty))
      {...jsonDecode(line) as Map<String, dynamic>}..remove('ts'),
  ];
}
