// agent_step.dart — a single step in an agent pipeline
//
// An AgentStep is a self-contained unit of work:
//   - which model to call
//   - what system prompt to use
//   - how to build the message from current context
//   - which XML tag in the output triggers which route
//
// Routing:
//   routes is empty  → no branching; executor proceeds to next step in list
//   routes non-empty → executor parses output for first matching tag, routes accordingly
//
// All prompt building is deferred to buildPrompt(ctx) so steps are pure
// data — no I/O at declaration time. Tests can inject any PipelineContext.

import 'agent_model.dart';
import 'pipeline_context.dart';
import 'step_route.dart';

class AgentStep {
  final String id;
  final String label;
  final AgentModel model;
  final String systemPrompt;
  final String Function(PipelineContext ctx) buildPrompt;

  /// Tag-to-route map. The executor finds the first tag present in the step's
  /// output and follows its route. Order matters: entries are checked in
  /// insertion order (Dart Map preserves insertion order).
  final Map<String, StepRoute> routes;

  const AgentStep({
    required this.id,
    required this.label,
    required this.model,
    required this.systemPrompt,
    required this.buildPrompt,
    this.routes = const {},
  });
}
