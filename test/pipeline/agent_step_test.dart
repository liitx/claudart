// agent_step_test.dart — AgentStep.effectiveModel contract.
//
// Two rows:
//   - no selector → returns the static `model`
//   - selector wired → its return value wins (selector is total —
//     `AgentModel Function(ctx)`, not nullable, so there is no
//     "selector returns null" branch to test)
//
// Pure unit tests — no pipeline executor, no LLM.

import 'package:claudart/errors/claudart_exception.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agent_step.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/step_role.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';

PipelineContext _ctx() => const PipelineContext(
      projectRoot: _projectRoot,
      bug: '',
      expected: '',
      files: [],
    );

void main() {
  group('AgentStep.effectiveModel', () {
    test('no selector → returns the static `model`', () {
      final step = AgentStep(
        id: 'a',
        role: StepRole.classification,
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );
      expect(step.effectiveModel(_ctx()), equals(AgentModel.haiku));
    });

    test('selector returns a model → that model wins over `model`', () {
      final step = AgentStep(
        id: 'a',
        role: StepRole.classification,
        label: 'Step A',
        model: AgentModel.sonnet,
        modelSelector: (_) => AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );
      expect(step.effectiveModel(_ctx()), equals(AgentModel.haiku));
    });

    test('selector receives the ctx passed to effectiveModel', () {
      PipelineContext? captured;
      final step = AgentStep(
        id: 'a',
        role: StepRole.classification,
        label: 'Step A',
        model: AgentModel.sonnet,
        modelSelector: (ctx) {
          captured = ctx;
          return AgentModel.haiku;
        },
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );
      final ctx = _ctx();
      step.effectiveModel(ctx);
      expect(identical(captured, ctx), isTrue);
    });
  });
  // The role decides which models a step may run on. Haiku only classifies and
  // reads, so a reasoning or implementation step can never run on it.
  group('$AgentStep role guard', () {
    AgentStep stepWith({
      required StepRole role,
      required AgentModel model,
      ModelSelector? selector,
    }) =>
        AgentStep(
          id: 'a',
          label: 'Step A',
          role: role,
          model: model,
          modelSelector: selector,
          systemPrompt: 'sys',
          buildPrompt: (_) => 'msg',
        );

    test('a selector choosing a model the role forbids fails, typed', () {
      final step = stepWith(
        role: StepRole.reasoning,
        model: AgentModel.sonnet,
        selector: (_) => AgentModel.haiku,
      );
      expect(
        () => step.effectiveModel(_ctx()),
        throwsA(
          isA<ClaudartException>().having(
            (e) => e.failureType,
            'failureType',
            FailureType.stepModelNotPermittedForRole,
          ),
        ),
      );
    });

    test('a selector choosing a permitted model passes through', () {
      final step = stepWith(
        role: StepRole.reasoning,
        model: AgentModel.sonnet,
        selector: (_) => AgentModel.opus,
      );
      expect(step.effectiveModel(_ctx()), equals(AgentModel.opus));
    });

    test('a static model the role forbids fails when it is resolved', () {
      final step = stepWith(
        role: StepRole.implementation,
        model: AgentModel.haiku,
      );
      expect(
        () => step.effectiveModel(_ctx()),
        throwsA(
          isA<ClaudartException>().having(
            (e) => e.failureType,
            'failureType',
            FailureType.stepModelNotPermittedForRole,
          ),
        ),
      );
    });

    test('the failure context names the role and the model', () {
      final step = stepWith(
        role: StepRole.implementation,
        model: AgentModel.sonnet,
        selector: (_) => AgentModel.haiku,
      );
      try {
        step.effectiveModel(_ctx());
        fail('expected a ClaudartException');
      } on ClaudartException catch (error) {
        expect(
          error.context[StepRoleViolationField.role.name],
          equals(StepRole.implementation.name),
        );
        expect(
          error.context[StepRoleViolationField.model.name],
          equals(AgentModel.haiku.name),
        );
      }
    });
  });
}
