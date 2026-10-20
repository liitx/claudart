
// debug_steps.dart — AgentStep definitions for the debug pipeline
//
// Two linear steps:
//   [reader]      haiku  — reads scope files, emits raw file contents
//   [implementer] sonnet — generates file edits from handoff + file contents
//
// On PipelineCompleted, the caller parses the file blocks and writes to disk.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent_model.dart';
import '../agent_step.dart';
import '../step_role.dart';
import '../agents/categorization.dart';
import '../pipeline_context.dart';
import '../xml_tags.dart';

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
      '  - Never edit files on disk yourself. Your only output is the tags '
      'below; the owner approves the write.\n'
      '  - A file body is written verbatim and may contain tag text. A file '
      'block ends at the first closing tag that is followed only by whitespace '
      'and then another file block or the end of your output.\n'
      '  - Output ONLY the structured XML tags below. No prose outside tags.\n\n'
      'Output format:\n'
      '<$kChangesTagName>\n'
      'Human-readable description of what was changed and why.\n'
      '</$kChangesTagName>\n'
      'For each file modified:\n'
      '<$kEditFileTagName path="relative/path/to/file.dart">\n'
      'complete new file content\n'
      '</$kEditFileTagName>';

  static AgentStep reader(int fileCount) => AgentStep(
    id:           PipelineSlot.reader.key,
    label:        'Reading $fileCount scope file${fileCount == 1 ? '' : 's'} (haiku)…',
    role:        StepRole.fileReading,
    model:        AgentModel.haiku,
    systemPrompt: _readerSystem,
    buildPrompt:  _readerPrompt,
    routes:       const {},
  );

  static const AgentStep implementer = AgentStep(
    id:            'implementer',
    label:         'Implementing fix…',
    role:         StepRole.implementation,
    model:         AgentModel.sonnet,
    modelSelector: _implementerModelSelector,
    systemPrompt:  _implementerSystem,
    buildPrompt:   _implementerPrompt,
    routes:        {},
    // NOT bare: --bare strictly requires ANTHROPIC_API_KEY/apiKeyHelper and
    // never reads OAuth or keychain (verified live — a normal OAuth-logged-in
    // session gets "Not logged in · Please run /login" under --bare). That's
    // the standard auth path for this whole pipeline (see defaultClaudeRunner's
    // session-isolation comment in pipeline_executor.dart), so bare would break
    // claudart debug for the common case, not just guard against CLAUDE.md
    // override. Revisit if/when this pipeline supports API-key-based auth.
  );

  /// Reads the categorize step's output — [runDebug] runs its own Phase 0
  /// categorize step rather than trusting anything suggest computed
  /// earlier, since Bug/Root Cause can change between the two commands —
  /// and consults [routeModel]. Falls back to sonnet when the slot is
  /// empty or unparsable.
  static AgentModel _implementerModelSelector(PipelineContext ctx) =>
      modelForCategorizeOutput(
        ctx[PipelineSlot.categorize] ?? '',
        fallback: AgentModel.sonnet,
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