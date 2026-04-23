// pipeline_component.dart — executor mechanics as dartrix ComponentType
//
// Each value is a reusable mechanical unit of PipelineExecutor, orthogonal
// to step content. Used by claudart_matrix.dart to derive component coverage.

import 'package:dartrix/dartrix.dart';

enum PipelineComponent implements ComponentType {
  spinner(description: 'Animated spinner with step label and completion stats'),
  router(description: 'XML tag router — maps output tags to StepRoute variants'),
  tokenTracker(description: 'Usage accumulator — sums tokens and cost per run'),
  questionBranch(description: 'Question branch — delegates to lookup step'),
  userEscalation(description: 'User escalation — prompts user when lookup fails');

  const PipelineComponent({required this.description});

  @override
  final String description;
}
