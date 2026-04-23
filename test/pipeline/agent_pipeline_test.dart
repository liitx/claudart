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
import 'mock_claude_runner.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

String _fixture(String name) {
  final file = File('test/pipeline/fixtures/$name');
  return file.existsSync() ? file.readAsStringSync() : '';
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
      final mock = MockClaudeRunner({'reader': _readerXml});
      final exec = PipelineExecutor(runner: mock.runner);
      final ctx  = await exec.runFuture(
        steps:        [SuggestSteps.reader(1)],
        ctx:          _baseCtx(),
        displayStep:  1,
        displayTotal: 3,
      );

      expect(ctx.readerOut, contains('FINDINGS'));
      expect(mock.captured, hasLength(1));
      expect(mock.captured.first.model, equals(AgentModel.haiku));
    },
  );

  // ── suggest × reasoner ─────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.reasoner),
    (sel) async {
      final mock = MockClaudeRunner({'reasoner': _reasonerXml});
      final exec = PipelineExecutor(runner: mock.runner);
      final ctx  = await exec.runFuture(
        steps:        [SuggestSteps.reasoner],
        ctx:          _baseCtx().withSlot('reader', _readerXml),
        displayStep:  2,
        displayTotal: 3,
      );

      expect(ctx.reasonerOut, contains('ROOT_CAUSE'));
      expect(ctx.reasonerOut, contains('SCOPE_FILES'));
      expect(mock.captured.first.model, equals(AgentModel.sonnet));
    },
  );

  // ── suggest × planner ──────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.suggest.getSelector(PipelineFeature.planner),
    (sel) async {
      final mock = MockClaudeRunner({'planner': _plannerXml});
      final exec = PipelineExecutor(runner: mock.runner);
      final ctx  = await exec.runFuture(
        steps: SuggestSteps.refinement(1),
        ctx: _baseCtx()
            .withSlot('reader',        _readerXml)
            .withSlot('reasoner',      _reasonerXml)
            .withSlot('user_feedback', 'Add null safety check for label'),
        displayStep:  2,
        displayTotal: 3,
      );

      // Planner emitted CHANGES → GoTo(applier) → applier ran
      expect(ctx['applier'] ?? ctx['planner'], contains('CHANGES'),
          reason: 'planner output should contain CHANGES tag');
      expect(mock.captured.first.model, equals(AgentModel.sonnet));
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
      final mock = MockClaudeRunner({});
      ClaudeRunner countingRunner = ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
      }) async {
        mock.captured.add(CallRecord(model: model, systemPrompt: systemPrompt, message: message));
        if (model == AgentModel.haiku) {
          return (text: answerXml, usage: const Usage(input: 50, output: 20, cost: 0.0005, cacheRead: 0));
        }
        plannerCallCount++;
        final text = plannerCallCount == 1 ? questionXml : _plannerXml;
        return (text: text, usage: const Usage(input: 200, output: 80, cost: 0.002, cacheRead: 0));
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
      // Mock: planner → CHANGES; applier → updated XML
      var step = 0;
      ClaudeRunner twoStepRunner = ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
      }) async {
        step++;
        final text = step == 1 ? _plannerXml : _applierXml;
        return (text: text, usage: const Usage(input: 100, output: 50, cost: 0.001, cacheRead: 0));
      };

      final exec = PipelineExecutor(runner: twoStepRunner);
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
    final mock = MockClaudeRunner({
      'reader':   _readerXml,
      'reasoner': _reasonerXml,
    });
    final exec = PipelineExecutor(runner: mock.runner);

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
      final mock = MockClaudeRunner({'categorize': categorizeXml});
      final exec = PipelineExecutor(runner: mock.runner, prompter: (_) async => 'y');
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.categorize],
        ctx:          _baseCtx(),
        displayStep:  1,
        displayTotal: 3,
      );

      expect(ctx['categorize'], contains('CATEGORY'));
      expect(mock.captured.first.model, equals(AgentModel.haiku));
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
      var callCount = 0;
      Future<({String text, Usage usage})?> twoStepRunner({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
      }) async {
        callCount++;
        final text = callCount == 1 ? planXml : constructXml;
        return (text: text, usage: const Usage(input: 100, output: 50, cost: 0.001, cacheRead: 0));
      }
      final exec = PipelineExecutor(runner: twoStepRunner, prompter: (_) async => 'y');
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.plan, FlowSteps.construct],
        ctx:          _baseCtx().withSlot('categorize', '<CATEGORY>feature</CATEGORY>'),
        displayStep:  2,
        displayTotal: 3,
      );

      expect(ctx['plan'] ?? ctx['construct'], isNotNull);
    },
  );

  // ── flow × construct ───────────────────────────────────────────────────────

  testSelector(
    claudartMatrix,
    PipelineFlowType.flow.getSelector(PipelineFeature.construct),
    (sel) async {
      const handoffXml =
          '<HANDOFF>## Status\nready-for-debug\n## Bug/Goal\nFix null label</HANDOFF>';
      final mock = MockClaudeRunner({'construct': handoffXml});
      final exec = PipelineExecutor(runner: mock.runner, prompter: (_) async => '');
      final ctx  = await exec.runFuture(
        steps:        [FlowSteps.construct],
        ctx:          _baseCtx().withSlot('plan', '<PLAN>1. Fix label\n</PLAN>'),
        displayStep:  3,
        displayTotal: 3,
      );

      expect(ctx['construct'], contains('HANDOFF'));
      expect(mock.captured.first.model, equals(AgentModel.sonnet));
    },
  );

  // ── Matrix gap assertion ───────────────────────────────────────────────────

  assertNoGaps();
}
