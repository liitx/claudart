// plan_step_routing_test.dart — verifies the plan step's modelSelector
// actually wires the categorize output to the τ matrix.
//
// Two paths:
//   well-formed atomic-explore categorize → sonnet (haiku never reasons)
//   missing / empty categorize             → fallback sonnet

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agents/categorization.dart';
import 'package:claudart/pipeline/flows/flow_steps.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';
const _bug = 'a real task';
const _expected = 'should work';

PipelineContext _baseCtx() => const PipelineContext(
      projectRoot: _projectRoot,
      bug: _bug,
      expected: _expected,
      files: [],
    );

PipelineContext _ctxWithCategorize(String categorizeOutput) =>
    _baseCtx().withSlot(PipelineSlot.categorize, categorizeOutput);

String _categorize({
  required AgentCategory category,
  required IntentClass intent,
  required ComplexityTier complexity,
}) =>
    '<${CategorizeTag.category.wireTag}>${category.name}</${CategorizeTag.category.wireTag}>\n'
    '<${CategorizeTag.intent.wireTag}>${intent.name}</${CategorizeTag.intent.wireTag}>\n'
    '<${CategorizeTag.complexity.wireTag}>${complexity.name}</${CategorizeTag.complexity.wireTag}>\n';

void main() {
  test('plan step routes atomic-explore to sonnet, never haiku', () {
    final ctx = _ctxWithCategorize(_categorize(
      category: AgentCategory.feature,
      intent: IntentClass.explore,
      complexity: ComplexityTier.atomic,
    ));
    expect(FlowSteps.plan.effectiveModel(ctx), equals(AgentModel.sonnet));
  });

  test('plan step routes systemic-explore to opus', () {
    final ctx = _ctxWithCategorize(_categorize(
      category: AgentCategory.research,
      intent: IntentClass.explore,
      complexity: ComplexityTier.systemic,
    ));
    expect(FlowSteps.plan.effectiveModel(ctx), equals(AgentModel.opus));
  });

  test('plan step degrades to sonnet when categorize slot is empty', () {
    expect(FlowSteps.plan.effectiveModel(_baseCtx()),
        equals(AgentModel.sonnet));
  });

  test('plan step degrades to sonnet on malformed categorize output', () {
    final ctx = _ctxWithCategorize('garbage with no xml tags');
    expect(FlowSteps.plan.effectiveModel(ctx), equals(AgentModel.sonnet));
  });

  // construct shares plan's modelSelector — a gui × design task should get
  // opus writing the handoff too, not just planning it. Same silent-skip
  // gap suggest/debug's reasoner/implementer had before this session's fix,
  // closed here for flow's construct step.
  test('construct step routes gui × design to opus, same as plan', () {
    final ctx = _ctxWithCategorize(_categorize(
      category: AgentCategory.gui,
      intent: IntentClass.design,
      complexity: ComplexityTier.systemic,
    ));
    expect(FlowSteps.construct.effectiveModel(ctx), equals(AgentModel.opus));
  });

  test('construct step degrades to sonnet when categorize slot is empty', () {
    expect(FlowSteps.construct.effectiveModel(_baseCtx()),
        equals(AgentModel.sonnet));
  });
}
