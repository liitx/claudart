// event_usage.dart — which lib/ files pass each HandoffEvent.
//
// Shared by the generated topology doc and the drift tests that check a
// command's declared handoffEvents against what the code actually does.

import 'dart:io';

import 'package:claudart/session/handoff_event.dart';

const _libDir = 'lib';

/// The files that define or declare events; mentions there are not callers.
/// `claudart_command.dart` declares which events each command passes
/// (`handoffEvents`); the commands themselves are the callers.
const _tableFiles = {
  'lib/session/handoff_event.dart',
  'lib/session/session_state.dart',
  'lib/commands/claudart_command.dart',
};

final _eventMention = RegExp(r'HandoffEvent\.(\w+)');

/// Event -> files (relative paths, sorted) that mention it, ignoring the
/// files that define the table.
Map<HandoffEvent, List<String>> usageByEvent(Map<String, String> sources) {
  final byName = {for (final event in HandoffEvent.values) event.name: event};
  final used = <HandoffEvent, Set<String>>{
    for (final event in HandoffEvent.values) event: {},
  };
  for (final entry in sources.entries) {
    if (_tableFiles.contains(entry.key)) continue;
    for (final match in _eventMention.allMatches(entry.value)) {
      final event = byName[match.group(1)];
      if (event != null) used[event]!.add(entry.key);
    }
  }
  return {
    for (final event in HandoffEvent.values)
      event: used[event]!.toList()..sort(),
  };
}

/// Every `lib/**/*.dart` source, keyed by its project-relative path.
Map<String, String> readLibSources() => {
      for (final file in Directory(_libDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: file.readAsStringSync(),
    };
