// debug_steps.dart — AgentStep definitions for the debug pipeline
//
// Two linear steps:
//   [reader]      haiku  — reads scope files, emits raw file contents
//   [implementer] sonnet — generates file edits from handoff + file contents
//
// On PipelineCompleted, the caller parses <EDIT_FILE> tags and writes to disk.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent_model.dart';
import '../agent_step.dart';
import '../pipeline_context.dart';
import '../pipeline_slot.dart';

abstract final class DebugSteps {
  static const String _readerSystem =
      'You are a precise code reader. Read the listed files and return their '
      'complete, verbatim contents. Do not summarize, truncate, or modify anything.';

  static const String _implementerSystem =
      'You are a DEBUG agent — deterministic, scoped implementation.\n'
      'Rules:\n'
      '  - Execute the fix path defined in the handoff exactly.\n'
      '  - Minimal diff only. No refactoring of surrounding code.\n'
      '  - Do not touch files listed under Must not touch.\n'
      '  - Only reference types, classes, and enums present in the file contents '
      'and known types list provided. Do not invent or assume types.\n'
      '  - Output ONLY the structured XML tags below. No prose outside tags.\n\n'
      'Output format:\n'
      '<CHANGES>\n'
      'Human-readable description of what was changed and why.\n'
      '</CHANGES>\n'
      'For each file modified:\n'
      '<EDIT_FILE path="relative/path/to/file.dart">\n'
      'complete new file content\n'
      '</EDIT_FILE>';

  static AgentStep reader(int fileCount) => AgentStep(
    id:           PipelineSlot.reader.key,
    label:        'Reading $fileCount scope file${fileCount == 1 ? '' : 's'} (haiku)…',
    model:        AgentModel.haiku,
    systemPrompt: _readerSystem,
    buildPrompt:  _readerPrompt,
    routes:       const {},
  );

  static const AgentStep implementer = AgentStep(
    id:           'implementer',
    label:        'Implementing fix (sonnet)…',
    model:        AgentModel.sonnet,
    systemPrompt: _implementerSystem,
    buildPrompt:  _implementerPrompt,
    routes:       {},
  );

  static const List<AgentStep> all = [implementer];

  static List<AgentStep> forScope(int fileCount) => [reader(fileCount), implementer];
}

// ── Prompt builders ───────────────────────────────────────────────────────────

String _readerPrompt(PipelineContext ctx) => '''
${ctx.bug}

Read each file below completely. Return them verbatim with no changes.
Wrap each in:  === FILE: <path> ===\n<content>\n=== END ===

Files:
${ctx.files.map((f) => f.absolute).join('\n')}
''';

String _implementerPrompt(PipelineContext ctx) => '''
${ctx.bug}

${_enumInventory(ctx.projectRoot)}

File contents:
${ctx.readerOut}

Implement the fix strictly as specified. Output <CHANGES> and one <EDIT_FILE> per modified file.
''';

// Returns a one-line inventory of all enum types defined in lib/src/enums/.
// Injected into the implementer prompt so it cannot reference types that do not exist.
String _enumInventory(String projectRoot) {
  final enumDir = Directory(p.join(projectRoot, 'lib', 'src', 'enums'));
  if (!enumDir.existsSync()) return '';
  final names = <String>[];
  for (final file in enumDir.listSync().whereType<File>()) {
    for (final line in file.readAsLinesSync()) {
      final m = RegExp(r'^enum\s+(\w+)').firstMatch(line);
      if (m != null) names.add(m.group(1)!);
    }
  }
  if (names.isEmpty) return '';
  return 'Known local enum types (lib/src/enums/): ${names.join(', ')}.\n'
      'External package enums declared in the handoff scope are permitted.';
}
