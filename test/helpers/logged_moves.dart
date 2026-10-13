import 'dart:convert';

import 'package:claudart/paths.dart';
import 'package:path/path.dart' as p;

import 'mocks.dart';

/// The handoff moves a command logged to `<workspace>/logs/transitions.jsonl`,
/// minus the timestamp, so a test can compare them to exact typed values.
List<Map<String, dynamic>> loggedMoves(MemoryFileIO io, String workspace) {
  final raw = io.read(p.join(logsDirFor(workspace), 'transitions.jsonl'));
  return [
    for (final line in raw.split('\n').where((l) => l.isNotEmpty))
      {...jsonDecode(line) as Map<String, dynamic>}..remove('ts'),
  ];
}
