// pipeline_executor_test.dart — PipelineExecutor mechanics: postProcess and
// mode, isolated from any real flow/suggest/debug business steps.
//
// agent_pipeline_test.dart covers PipelineFlowType × PipelineFeature — the
// business flows. This file covers the executor's own step-independent
// contracts: postProcess rewrites what's stored and routed on, and mode
// reaches the runner. Minimal custom AgentSteps, no LLM.

import 'dart:async';

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agent_step.dart';
import 'package:claudart/pipeline/debug_mode.dart' show StepDebugTrace;
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_event.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/route_tag.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/tool_grant.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/step_route.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';

Future<String> _capturePrinted(Future<void> Function() action) async {
  final output = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => output.add(line),
    ),
  );
  return output.join('\n');
}

PipelineContext _ctx() => const PipelineContext(
      projectRoot: _projectRoot,
      bug: '',
      expected: '',
      files: [],
    );

void main() {
  group('PipelineExecutor — postProcess', () {
    test('stores the postProcess result, not the raw runner output', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
        postProcess: (raw, ctx) => raw.toUpperCase(),
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            StepResult(text: 'raw output', usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0)),
      );

      final ctx = await exec.runFuture(
        steps: [step],
        ctx: _ctx(),
        displayStep: 1,
        displayTotal: 1,
      );

      expect(ctx['a'], equals('RAW OUTPUT'));
    });

    test('routing matches against the postProcess result, not the raw text — '
        'lets postProcess inject a tag the raw output never emitted', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
        routes: const {RouteTag.handoff: Complete()},
        postProcess: (raw, ctx) => '<${RouteTag.handoff.wireTag}>$raw</${RouteTag.handoff.wireTag}>',
      );
      // A second step that would only ever run via routing fallthrough —
      // run() advances to the next step in `steps` when no route matches.
      // If it starts, routing missed the tag postProcess injected (i.e.
      // matched against the raw, untagged text instead).
      final decoy = AgentStep(
        id: 'decoy',
        label: 'Decoy',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            StepResult(text: 'no tags here', usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0)),
      );

      final events = await exec
          .run(steps: [step, decoy], ctx: _ctx(), displayStep: 1, displayTotal: 2)
          .toList();

      // Note: PipelineCompleted always fires exactly once regardless of
      // whether a route matched (a fallthrough past the last step also
      // completes) — asserting on it alone wouldn't prove routing used the
      // injected tag. Asserting decoy never started does: Complete()
      // terminates the pipeline immediately after step 'a' only if the
      // tag postProcess injected was actually matched.
      final startedIds = events.whereType<AgentStarted>().map((e) => e.stepId).toList();
      expect(startedIds, equals(['a']));
      expect(events.whereType<PipelineCompleted>(), hasLength(1));
    });

    test('no postProcess set → raw output stored unchanged', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            StepResult(text: 'unchanged', usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0)),
      );

      final ctx = await exec.runFuture(
        steps: [step],
        ctx: _ctx(),
        displayStep: 1,
        displayTotal: 1,
      );

      expect(ctx['a'], equals('unchanged'));
    });
  });

  group('PipelineExecutor — AgentCompleted forwards StepResult metadata', () {
    test('thinking/stopReason/durationMs/numTurns reach the emitted event, '
        'not just the parsing helpers that produce them', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            const StepResult(
              text: 'answer',
              usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
              thinking: 'reasoning text',
              stopReason: 'end_turn',
              durationMs: 4321,
              numTurns: 3,
            ),
      );

      final events = await exec
          .run(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1)
          .toList();

      final completed = events.whereType<AgentCompleted>().single;
      expect(completed.thinking, equals('reasoning text'));
      expect(completed.stopReason, equals('end_turn'));
      expect(completed.durationMs, equals(4321));
      expect(completed.numTurns, equals(3));
    });

    test('null metadata fields on StepResult forward as null, not dropped '
        'silently or defaulted', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            const StepResult(
              text: 'answer',
              usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
            ),
      );

      final events = await exec
          .run(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1)
          .toList();

      final completed = events.whereType<AgentCompleted>().single;
      expect(completed.thinking, isNull);
      expect(completed.stopReason, isNull);
      expect(completed.durationMs, isNull);
      expect(completed.numTurns, isNull);
    });
  });

  group('PipelineExecutor — AgentFailed.reason', () {
    final step = AgentStep(
      id: 'a',
      label: 'Step A',
      model: AgentModel.haiku,
      systemPrompt: 'sys',
      buildPrompt: (_) => 'msg',
    );

    test('a thrown Exception from the runner surfaces as AgentFailed.reason',
        () async {
      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            throw Exception('claude exited 1: boom'),
      );

      final events = await exec
          .run(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1)
          .toList();

      final failed = events.whereType<AgentFailed>().single;
      expect(failed.reason, contains('claude exited 1: boom'));
    });

    test('a runner returning null with no thrown exception leaves reason '
        'null, not a synthesized message', () async {
      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            null,
      );

      final events = await exec
          .run(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1)
          .toList();

      final failed = events.whereType<AgentFailed>().single;
      expect(failed.reason, isNull);
    });
  });

  group('PipelineExecutor — AgentStarted.isRevisit', () {
    test('false the first time a step runs, true when a route loops back to it', () async {
      // 'plan' routes to 'clarify' via QuestionBranch; 'clarify' routes
      // back to 'plan' via FeedBackTo; plan's second call emits HANDOFF,
      // routed to Complete() so the pipeline terminates cleanly instead of
      // falling through to "advance to next step" (which would bounce
      // plan/clarify forever with only two steps in the list). The exact
      // plan → clarify → plan loop shape flow_steps.dart uses for real.
      //
      // Distinct models (not distinct message strings) distinguish which
      // step is calling in the shared runner below — comparing `model`
      // keeps the check a typed AgentModel comparison, not a bare string.
      var planCalls = 0;
      final plan = AgentStep(
        id:    'plan',
        label: 'Plan',
        model: AgentModel.sonnet,
        systemPrompt: 'sys',
        buildPrompt:  (_) => 'msg',
        routes: {
          RouteTag.question: const QuestionBranch('clarify'),
          RouteTag.handoff:  const Complete(),
        },
      );
      final clarify = AgentStep(
        id:    'clarify',
        label: 'Clarify',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt:  (_) => 'msg',
        routes: {
          RouteTag.answer: const FeedBackTo('plan'),
        },
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async {
          if (model == plan.model) {
            planCalls++;
            if (planCalls == 1) {
              return StepResult(
                text:  '<${RouteTag.question.wireTag}>what?</${RouteTag.question.wireTag}>',
                usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
              );
            }
            return StepResult(
              text:  '<${RouteTag.handoff.wireTag}>done</${RouteTag.handoff.wireTag}>',
              usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
            );
          }
          return StepResult(
            text:  '<${RouteTag.answer.wireTag}>ok</${RouteTag.answer.wireTag}>',
            usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
          );
        },
      );

      final events = await exec
          .run(steps: [plan, clarify], ctx: _ctx(), displayStep: 1, displayTotal: 2)
          .toList();

      final started = events.whereType<AgentStarted>().toList();
      expect(started.map((e) => e.stepId).toList(), equals(['plan', 'clarify', 'plan']));
      expect(started[0].isRevisit, isFalse, reason: 'plan\'s first run');
      expect(started[1].isRevisit, isFalse, reason: 'clarify\'s first run');
      expect(started[2].isRevisit, isTrue, reason: 'plan, looped back to via clarify\'s FeedBackTo');
    });
  });

  group('PipelineExecutor — mode', () {
    test('AgentStep.mode reaches the runner call', () async {
      StepMode? capturedMode;
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
        mode: StepMode.bare,
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async {
          capturedMode = mode;
          return StepResult(text: '', usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0));
        },
      );

      await exec.runFuture(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1);

      expect(capturedMode, equals(StepMode.bare));
    });

    test('AgentStep.mode defaults to project', () async {
      StepMode? capturedMode;
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
      );

      final exec = PipelineExecutor(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async {
          capturedMode = mode;
          return StepResult(text: '', usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0));
        },
      );

      await exec.runFuture(steps: [step], ctx: _ctx(), displayStep: 1, displayTotal: 1);

      expect(capturedMode, equals(StepMode.project));
    });
  });

  group('PipelineExecutor.runFuture — verbose trace output', () {
    AgentStep rewritingStep() => AgentStep(
          id: 'a',
          label: 'Step A',
          model: AgentModel.haiku,
          systemPrompt: 'sys',
          buildPrompt: (_) => 'msg',
          postProcess: (raw, ctx) => raw.toUpperCase(),
        );

    ClaudeRunner staticRunner(String text) => ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async =>
            StepResult(text: text, usage: const Usage(input: 1, output: 1, cacheRead: 0, cost: 0));

    test('verbose: true prints the trace line when postProcess rewrites output', () async {
      final exec = PipelineExecutor(runner: staticRunner('raw'), verbose: true);

      final printed = await _capturePrinted(() => exec.runFuture(
            steps: [rewritingStep()],
            ctx: _ctx(),
            displayStep: 1,
            displayTotal: 1,
          ));

      expect(printed, contains('postProcess fired on "a"'));
    });

    test('verbose: false never prints the trace line, even when postProcess rewrites', () async {
      final exec = PipelineExecutor(runner: staticRunner('raw'));

      final printed = await _capturePrinted(() => exec.runFuture(
            steps: [rewritingStep()],
            ctx: _ctx(),
            displayStep: 1,
            displayTotal: 1,
          ));

      expect(printed, isNot(contains('postProcess fired')));
    });

    test('verbose: true but postProcess does not change the output — no trace line', () async {
      final step = AgentStep(
        id: 'a',
        label: 'Step A',
        model: AgentModel.haiku,
        systemPrompt: 'sys',
        buildPrompt: (_) => 'msg',
        postProcess: (raw, ctx) => raw, // identity — never "rewrites"
      );
      final exec = PipelineExecutor(runner: staticRunner('raw'), verbose: true);

      final printed = await _capturePrinted(() => exec.runFuture(
            steps: [step],
            ctx: _ctx(),
            displayStep: 1,
            displayTotal: 1,
          ));

      expect(printed, isNot(contains('postProcess fired')));
    });
  });

  group('consumeClaudeStream — real stream-json shapes, no mocks', () {
    test('accumulates thinking text across content_block_delta events and '
        'reads the thinking-token count off message_delta', () async {
      final lines = [
        '{"type":"stream_event","event":{"type":"message_start"}}',
        '{"type":"stream_event","event":{"type":"content_block_start"}}',
        '{"type":"stream_event","event":{"type":"content_block_delta",'
            '"delta":{"type":"thinking_delta","thinking":"Let me "}}}',
        '{"type":"stream_event","event":{"type":"content_block_delta",'
            '"delta":{"type":"thinking_delta","thinking":"check the code."}}}',
        // A text_delta must never leak into the thinking buffer.
        '{"type":"stream_event","event":{"type":"content_block_delta",'
            '"delta":{"type":"text_delta","text":"Final answer."}}}',
        '{"type":"stream_event","event":{"type":"message_delta",'
            '"usage":{"output_tokens_details":{"thinking_tokens":42}}}}',
        '{"type":"result","result":"Final answer.","stop_reason":"end_turn"}',
      ];

      final result = await consumeClaudeStream(
        Stream.fromIterable(lines),
        StepDebugTrace.disabled(),
      );

      expect(result.thinking, equals('Let me check the code.'));
      expect(result.thinkingTokens, equals(42));
      expect(result.lines, equals(lines));
    });

    test('malformed and irrelevant lines are ignored, not thrown', () async {
      final lines = [
        'not json at all',
        '{"type":"stream_event","event":{"type":"message_stop"}}',
        '{"type":"stream_event"}', // no "event" key content shape variance
        '',
        '   ',
      ];

      final result = await consumeClaudeStream(
        Stream.fromIterable(lines),
        StepDebugTrace.disabled(),
      );

      expect(result.thinking, isNull);
      expect(result.thinkingTokens, equals(0));
      // Blank lines are skipped entirely — never collected.
      expect(result.lines, equals([
        'not json at all',
        '{"type":"stream_event","event":{"type":"message_stop"}}',
        '{"type":"stream_event"}',
      ]));
    });

    test('valid JSON that is not an object at any level is ignored, not '
        'thrown — a bare null/array/number/string decodes successfully but '
        'is the wrong shape for every level this parser expects', () async {
      final lines = [
        'null', // top-level: valid JSON, not a Map
        '[1, 2, 3]', // top-level: valid JSON, not a Map
        '"just a string"', // top-level: valid JSON, not a Map
        '42', // top-level: valid JSON, not a Map
        '{"type":"stream_event","event":"not an object"}', // event: wrong shape
        '{"type":"stream_event","event":{"type":123}}', // event.type: not a String
        '{"type":"stream_event","event":{"type":"content_block_delta",'
            '"delta":"not an object"}}', // delta: wrong shape
        '{"type":"stream_event","event":{"type":"message_delta",'
            '"usage":"not an object"}}', // usage: wrong shape
        '{"type":"stream_event","event":{"type":"message_delta",'
            '"usage":{"output_tokens_details":"not an object"}}}', // details: wrong shape
      ];

      // The point of this test: none of the above throws. If any line
      // regresses to an unguarded `as Map<...>`/`as String?` cast, this
      // await throws a TypeError and the test fails.
      final result = await consumeClaudeStream(
        Stream.fromIterable(lines),
        StepDebugTrace.disabled(),
      );

      expect(result.thinking, isNull);
      expect(result.thinkingTokens, equals(0));
      expect(result.lines, equals(lines));
    });
  });

  group('parseClaudeResultLine — final result-line → StepResult', () {
    test('extracts text, usage, stop_reason, duration_ms, and num_turns', () {
      const resultLine = '{"type":"result","result":"The answer.",'
          '"stop_reason":"end_turn","duration_ms":4321,"num_turns":3,'
          '"total_cost_usd":0.05,'
          '"usage":{"input_tokens":10,"output_tokens":20,'
          '"cache_read_input_tokens":5,"cache_creation_input_tokens":2}}';

      final result = parseClaudeResultLine(
        resultLine,
        thinkingBuffer: 'reasoning text',
        thinkingTokens: 42,
      );

      expect(result.text, equals('The answer.'));
      expect(result.thinking, equals('reasoning text'));
      expect(result.stopReason, equals('end_turn'));
      expect(result.durationMs, equals(4321));
      expect(result.numTurns, equals(3));
      expect(result.usage.input, equals(10));
      expect(result.usage.output, equals(20));
      expect(result.usage.cacheRead, equals(5));
      expect(result.usage.cacheCreation, equals(2));
      expect(result.usage.cost, equals(0.05));
      expect(result.usage.thinkingTokens, equals(42));
    });

    test('defaults stop_reason/duration_ms/num_turns to null when absent', () {
      const resultLine = '{"type":"result","result":"ok"}';

      final result = parseClaudeResultLine(
        resultLine,
        thinkingBuffer: null,
        thinkingTokens: 0,
      );

      expect(result.stopReason, isNull);
      expect(result.durationMs, isNull);
      expect(result.numTurns, isNull);
      expect(result.thinking, isNull);
    });
  });
}
