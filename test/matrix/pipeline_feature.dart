// pipeline_feature.dart — pipeline step types as dartrix FeatureType
//
// Each value represents a user-observable capability of the agent pipeline.
// Used by claudart_matrix.dart to declare coverage obligations.

import 'package:dartrix/dartrix.dart';

enum PipelineFeature implements FeatureType {
  reader(description: 'Read scope files and emit structured findings'),
  reasoner(description: 'Reason over findings to produce root cause and scope'),
  planner(description: 'Plan changes from feedback; delegate questions to lookup'),
  lookup(description: 'Search phase-1 findings to answer planner questions'),
  applier(description: 'Apply change plan to XML output sections'),
  categorize(description: 'Classify freeform input into AgentCategory × IntentClass × ComplexityTier'),
  planStep(description: 'Generate dependency-ordered plan; emit PLAN or QUESTION'),
  construct(description: 'Construct full handoff from approved plan');

  const PipelineFeature({required this.description});

  @override
  final String description;
}
