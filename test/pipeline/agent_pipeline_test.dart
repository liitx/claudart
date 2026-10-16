// agent_pipeline_test.dart — unit tests for the claudart pipeline engine
//
// Tests are structured by PipelineFlowType × PipelineFeature.
// Each testSelector call registers coverage in claudartMatrix.
// assertNoGaps() at end verifies no required pair is left untested.

import 'dart:io';

import 'package:claudart/claudart.dart';
import 'package:claudart/pipeline/flows/flow_steps.dart';
import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

import '../matrix/claudart_matrix.dart';
import '../matrix/pipeline_feature.dart';
import '../matrix/pipeline_flow_type.dart';
import '../helpers/scripted_claude_runner.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

String _fixture(String name) {
  final file = File('test/pipeline/fixtures/$name');
  if (!file.existsSync()) {
    // A missing fixture used to become '' and let tests assert on nothing.
    throw StateError('Missing test fixture: ${file.path}');
  }
  return file.readAsStringSync();
}

final _readerXml   = _fixture('reader_output.xml');
final _reasonerXml = _fixture('reasoner_output.xml');
final _plannerXml  = _fixture('planner_output.xml');
final _applierXml  = _fixture('applier_output.xml');

// ── Helpers ───────────────────────────────────────────────────────────────────

PipelineContext _baseCtx() => PipelineContext(
      projectRoot: '/tmp/test_project',
      bug:         'Label is null when not provided',
      expected:    'Widget shows default label',
      files:       [(relative: 'lib/example.dart', absolute: '/tmp/test_project/lib/example.dart')],
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── suggest × reader ───────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.reader),
    (sel) async {
      final fake = ScriptedClaudeRunner({SuggestSteps.reader(1): _readerXml});
      final exec = PipelineExecutor(runner: fake.runner);
      final ctx  = await exec.runFuture(
        steps:        [SuggestSteps.reader(1)],
        ctx:          _baseCtx(),
        displayStep:  1,
        displayTotal: 3,
      );

      expect(ctx.readerOut, contains('FINDINGS'));
      expect(fake.calls, hasLength(1));
      expect(fake.calls.first.model, equals(AgentModel.haiku));
      expect(fake.unusedSteps, isEmpty);
    },
  );

  // ── suggest × reasoner ─────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.reasoner),
    (sel) async {
      final fake = ScriptedClaudeRunner({SuggestSteps.reasoner: _reasonerXml});
      final exec = PipelineExecutor(runner: fake.runner);
      final ctx  = await exec.runFuture(
        steps:        [SuggestSteps.reasoner],
        ctx:          _baseCtx().withSlot('reader', _readerXml),
        displayStep:  2,
        displayTotal: 3,
      );

      expect(ctx.reasonerOut, contains('ROOT_CAUSE'));
      expect(ctx.reasonerOut, contains('SCOPE_FILES'));
      expect(fake.calls.first.model, equals(AgentModel.sonnet));
    },
  );

  // ── suggest × planner ──────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.planner),
    (sel) async {
      // Each reply is scripted for its own step, so the planner and the applier
      // cannot be confused (the postProcess merge this test exercises depends
      // on the applier getting the applier's text).
      final steps = SuggestSteps.refinement(1);
      final fake = ScriptedClaudeRunner({
        steps[0]: _plannerXml,
        steps[2]: _applierXml,
      });
      final exec = PipelineExecutor(runner: fake.runner);
      final ctx  = await exec.runFuture(
        steps: SuggestSteps.refinement(1),
        ctx: _baseCtx()
            .withSlot('reader',        _readerXml)
            .withSlot('reasoner',      _reasonerXml)
            .withSlot('user_feedback', 'Add null safety check for label'),
        displayStep:  2,
        displayTotal: 3,
      );

      // Planner emitted CHANGES → GoTo(applier) → applier ran, then its
      // output merged (via postProcess) into the full analysis document —
      // ctx['applier'] holds the merged sections, not the applier's raw
      // partial output.
      expect(ctx['planner'], contains('CHANGES'),
          reason: 'planner output should contain CHANGES tag');
      expect(ctx['applier'], contains('ROOT_CAUSE'),
          reason: 'applier output should hold the merged analysis sections');
      expect(fake.calls.first.model, equals(AgentModel.sonnet));
      expect(
        fake.calls.map((c) => c.systemPrompt),
        [steps[0].systemPrompt, steps[2].systemPrompt],
        reason: 'planner first, then the applier (the lookup step is skipped)',
      );
      expect(fake.unusedSteps, isEmpty);
    },
  );

  // ── suggest × lookup ───────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.lookup),
    (sel) async {
      // Planner emits QUESTION → lookup answers → planner runs again → CHANGES
      const questionXml = '<QUESTION>What is the type of the label field?</QUESTION>';
      const answerXml   = '<ANSWER>label is String? — nullable optional field</ANSWER>';

      // Second planner call produces CHANGES after receiving the answer
      var plannerCallCount = 0;
      ClaudeRunner countingRunner = ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
        StepMode mode = StepMode.project,
      }) async {
        if (model == AgentModel.haiku) {
          return StepResult(text: answerXml, usage: const Usage(input: 50, output: 20, cost: 0.0005, cacheRead: 0));
        }
        plannerCallCount++;
        final text = plannerCallCount == 1 ? questionXml : _plannerXml;
        return StepResult(text: text, usage: const Usage(input: 200, output: 80, cost: 0.002, cacheRead: 0));
      };

      final exec = PipelineExecutor(
        runner:   countingRunner,
        prompter: (_) async => '', // no user escalation expected
      );
      final ctx = await exec.runFuture(
        steps: SuggestSteps.refinement(1),
        ctx: _baseCtx()
            .withSlot('reader',        _readerXml)
            .withSlot('reasoner',      _reasonerXml)
            .withSlot('user_feedback', 'Check label nullability'),
        displayStep:  2,
        displayTotal: 3,
      );

      expect(plannerCallCount, equals(2), reason: 'planner should run twice: QUESTION then CHANGES');
      expect(ctx.usage.input, greaterThan(0));
    },
  );

  // ── suggest × applier ──────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.applier),
    (sel) async {
      // Planner → CHANGES; applier → updated XML, each scripted for its step.
      final steps = SuggestSteps.refinement(1);
      final fake = ScriptedClaudeRunner({
        steps[0]: _plannerXml,
        steps[2]: _applierXml,
      });

      final exec = PipelineExecutor(runner: fake.runner);
      final ctx  = await exec.runFuture(
        steps: SuggestSteps.refinement(1),
        ctx: _baseCtx()
            .withSlot('reader',        _readerXml)
            .withSlot('reasoner',      _reasonerXml)
            .withSlot('user_feedback', 'Add null check'),
        displayStep:  2,
        displayTotal: 3,
      );

      expect(ctx.applierOut, contains('CONSTRAINTS'));
      expect(ctx.applierOut, contains('null check'));
      expect(ctx.usage.input,  equals(200)); // 100 planner + 100 applier
      expect(ctx.usage.output, equals(100));
    },
  );

  // ── Usage accumulation (component: tokenTracker) ───────────────────────────

  test('usage accumulates across multiple steps', () async {
    final fake = ScriptedClaudeRunner({
      SuggestSteps.reader(1): _readerXml,
      SuggestSteps.reasoner:  _reasonerXml,
    });
    final exec = PipelineExecutor(runner: fake.runner);

    var ctx = _baseCtx();
    ctx = await exec.runFuture(steps: [SuggestSteps.reader(1)], ctx: ctx, displayStep: 1, displayTotal: 3);
    ctx = await exec.runFuture(steps: [SuggestSteps.reasoner],  ctx: ctx, displayStep: 2, displayTotal: 3);

    expect(ctx.usage.input,  equals(200)); // 100 + 100
    expect(ctx.usage.output, equals(100)); // 50 + 50
    expect(ctx.usage.cost,   closeTo(0.002, 0.0001));
  });

  // ── flow × categorize ─────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.flow.getSelector(PipelineFeature.categorize),
    (sel) async {
      const categorizeXml =
          '<CATEGORY>feature</CATEGORY>'
          '<INTENT>implement</INTENT>'
          '<COMPLEXITY>compound</COMPLEXITY>'
          '<MODEL>sonnet</MODEL>';
      final fake = ScriptedClaudeRunner({FlowSteps.categorize: categorizeXml});
      final exec = PipelineExecutor(
        runner:   fake.runner,
        prompter: (_) async => 'y',
      );
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.categorize],
        ctx:          _baseCtx(),
        displayStep:  1,
        displayTotal: 3,
      );

      expect(ctx['categorize'], contains('CATEGORY'));
      expect(fake.calls.first.model, equals(AgentModel.haiku));
    },
  );

  // ── flow × planStep ────────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.flow.getSelector(PipelineFeature.planStep),
    (sel) async {
      const planXml =
          '<PLAN>1. Add null check\n2. Update tests</PLAN>';
      const constructXml =
          '<HANDOFF>## Status\nready-for-debug\n## Bug/Goal\nAdd null check</HANDOFF>';
      final fake = ScriptedClaudeRunner({
        FlowSteps.plan:      planXml,
        FlowSteps.construct: constructXml,
      });
      final exec = PipelineExecutor(
        runner:           fake.runner,
        prompter:         (_) async => 'y',
        approvalSelector: (_) async => 0, // approve — inject so the gate needs no TTY
      );
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.plan, FlowSteps.construct],
        ctx:          _baseCtx().withSlot('categorize', '<CATEGORY>feature</CATEGORY>'),
        displayStep:  2,
        displayTotal: 3,
      );

      // Approved plan stored as scripted; the construct step then ran on it.
      expect(ctx['plan'], equals(planXml));
      expect(ctx['construct'], equals(constructXml));
      expect(
        fake.calls.map((c) => c.systemPrompt),
        [FlowSteps.plan.systemPrompt, FlowSteps.construct.systemPrompt],
        reason: 'plan runs first, then construct',
      );
      expect(fake.unusedSteps, isEmpty);
    },
  );

  // ── flow × construct ───────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.flow.getSelector(PipelineFeature.construct),
    (sel) async {
      const handoffXml =
          '<HANDOFF>## Status\nready-for-debug\n## Bug/Goal\nFix null label</HANDOFF>';
      final fake = ScriptedClaudeRunner({FlowSteps.construct: handoffXml});
      final exec = PipelineExecutor(
        runner:   fake.runner,
        prompter: (_) async => '',
      );
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.construct],
        ctx:          _baseCtx().withSlot('plan', '<PLAN>1. Fix label\n</PLAN>'),
        displayStep:  3,
        displayTotal: 3,
      );

      expect(ctx['construct'], contains('HANDOFF'));
      expect(fake.calls.first.model, equals(AgentModel.sonnet));
    },
  );

  // ── Matrix gap assertion ───────────────────────────────────────────────────

  assertNoGaps();
}
