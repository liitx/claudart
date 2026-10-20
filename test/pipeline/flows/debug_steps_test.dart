// debug_steps_test.dart — DebugSteps.implementer's `mode` contract.
//
// No dedicated test file existed for debug_steps.dart.

import 'package:claudart/pipeline/flows/debug_steps.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/xml_tags.dart';
import 'package:test/test.dart';

void main() {
  test('implementer runs in StepMode.project, NOT StepMode.bare — verified '
      'live that --bare requires ANTHROPIC_API_KEY/apiKeyHelper and never '
      'reads OAuth or keychain, which is this pipeline\'s standard auth '
      'path (a normal OAuth session gets "Not logged in" under --bare); '
      'StepMode.bare here would break claudart debug for the common case, '
      'not just guard against a project CLAUDE.md overriding the system '
      'prompt', () {
    expect(DebugSteps.implementer.mode, equals(StepMode.project));
  });

  // One test per rule: a rule dropped from the prompt fails by name.
  group('implementer system prompt states', () {
    const rules = <String>[
      'Execute the fix path defined in the handoff exactly.',
      'Minimal diff only. No refactoring of surrounding code.',
      'Do not touch files listed under Must not touch.',
      '  - Never edit files on disk yourself.',
      'the owner approves the write.',
      '  - A file body is written verbatim and may contain tag text.',
      'A file block ends at the first closing tag that is followed only by '
          'whitespace and then another file block or the end of your output.',
      'Output ONLY the structured XML tags below.',
      'Human-readable description of what was changed and why.',
      'path="relative/path/to/file.dart">',
      'complete new file content',
    ];
    for (final rule in rules) {
      test(rule, () {
        expect(DebugSteps.implementer.systemPrompt, contains(rule));
      });
    }
  });

  group('implementer system prompt names every wire tag', () {
    for (final tag in WireTag.values) {
      test(tag.name, () {
        final prompt = DebugSteps.implementer.systemPrompt;
        expect(prompt, contains(tag.openPrefix));
        expect(prompt, contains(tag.close));
      });
    }
  });
}
