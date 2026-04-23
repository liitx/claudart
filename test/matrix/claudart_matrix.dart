// claudart_matrix.dart — coverage matrix for the claudart pipeline
//
// Axes:  PipelineFlowType (suggest, debug, setup, save)
// Features: PipelineFeature (reader, reasoner, planner, lookup, applier)
//
// Each test registers coverage via testSelector. Running matrix.gaps() at
// end-of-suite asserts no required (flow × feature) pair is left untested.

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import 'pipeline_feature.dart';
import 'pipeline_flow_type.dart';

final claudartMatrix = Dartrix(
  axes:     [PipelineFlowType.values],
  features: PipelineFeature.values,
);

void assertNoGaps() {
  test('matrix: no coverage gaps', () {
    final gaps = claudartMatrix.gaps();
    if (gaps.isEmpty) return;
    final lines = gaps.map((g) => '  ${g.variant.description} × ${g.feature.description}');
    fail('Coverage gaps:\n${lines.join('\n')}');
  });
}
