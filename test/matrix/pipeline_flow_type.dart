// pipeline_flow_type.dart — AgentFlow variants as dartrix AppType
//
// Wraps AgentFlow as AppType so the matrix can derive coverage obligations
// per flow. Each variant declares which PipelineFeatures it exercises.
//
// Debug/setup/save are stubs — feature sets expand as flows are built.

import 'package:dartrix/dartrix.dart';

import 'pipeline_feature.dart';

enum PipelineFlowType implements AppType {
  suggest(
    description: 'Suggest flow — deep exploration, root cause, scope, constraints',
    features: {
      PipelineFeature.reader,
      PipelineFeature.reasoner,
      PipelineFeature.planner,
      PipelineFeature.lookup,
      PipelineFeature.applier,
    },
  ),
  debug(
    description: 'Debug flow — scoped implementation (stub)',
    features: {},
  ),
  setup(
    description: 'Setup flow — workspace init (stub)',
    features: {},
  ),
  save(
    description: 'Save flow — checkpoint session (stub)',
    features: {},
  ),
  flow(
    description: 'Flow flow — agent-constructed session: classify → plan → construct',
    features: {
      PipelineFeature.categorize,
      PipelineFeature.planStep,
      PipelineFeature.construct,
    },
  );

  const PipelineFlowType({required this.description, required this.features});

  @override
  final String description;

  @override
  final Set<PipelineFeature> features;
}
