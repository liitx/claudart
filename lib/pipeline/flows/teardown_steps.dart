// teardown_steps.dart — AgentStep for the teardown analyzer pipeline
//
// One step: analyzer (haiku) reads the completed handoff and extracts
// structured teardown metadata as XML tags.
//
// On PipelineCompleted, the caller parses the XML tags and writes to
// skills.md, archive, and resets the handoff.

import '../agent_model.dart';
import '../agent_step.dart';
import '../pipeline_context.dart';

abstract final class TeardownSteps {
  static const String slotKey = 'teardown-analyzer';

  static const String _analyzerSystem =
      'You analyze a completed debug session handoff and extract structured '
      'teardown metadata.\n\n'
      'Output ONLY the XML tags below — no prose, no explanation outside tags.\n\n'
      '<CATEGORY>one of: api-integration | concurrency | configuration | '
      'data-parsing | io-filesystem | state-management | general</CATEGORY>\n'
      '<FIX_SUMMARY>one or two sentences describing what was done to fix the '
      'issue</FIX_SUMMARY>\n'
      '<HOT_FILES>comma-separated list of files central to the fix, or '
      '"none"</HOT_FILES>\n'
      '<COLD_FILES>comma-separated list of files explored but NOT the root '
      'cause, or "none"</COLD_FILES>\n'
      '<ROOT_CAUSE_PATTERN>one generic sentence describing the root cause '
      'pattern, omitting project-specific names</ROOT_CAUSE_PATTERN>\n'
      '<FIX_PATTERN>one generic sentence describing the fix pattern, omitting '
      'project-specific names</FIX_PATTERN>';

  static const AgentStep analyzer = AgentStep(
    id:           slotKey,
    label:        'Analyzing session (haiku)…',
    model:        AgentModel.haiku,
    systemPrompt: _analyzerSystem,
    buildPrompt:  _buildPrompt,
    routes:       {},
  );
}

String _buildPrompt(PipelineContext ctx) => 'Handoff:\n\n${ctx.bug}';
