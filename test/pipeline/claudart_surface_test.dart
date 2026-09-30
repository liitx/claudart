// claudart_surface_test.dart — ClaudartSurface / SurfaceExecutorConfig
//
// Coverage:
//   - .cli() declares ClaudartSurface.cli and builds a PipelineExecutor.
//   - .tui() requires prompter (enforced by the compiler); omitting
//     approvalSelector still builds successfully.
//   - .build() wires runner and strict through to the built PipelineExecutor
//     for both surfaces.
//
// Note: PipelineExecutor itself has no public `surface` field — only
// SurfaceExecutorConfig carries the surface declaration (see
// claudart_surface.dart's own doc comment: "the executor's origin is
// queryable" refers to the config, not the built executor). Verified by
// compiler, not by reading source: `dart analyze` on a throwaway
// `PipelineExecutor().surface` reference raises `undefined_getter`.
// Coverage below asserts on the config's `surface` getter instead.
//
// Each test prints the case it ran and the value it observed — `dart test`
// output is a readable per-flavor report, not just a pass/fail count.

import 'package:claudart/pipeline/agent_model.dart';
import 'package:claudart/pipeline/agent_step.dart';
import 'package:claudart/pipeline/claudart_surface.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/pipeline/step_mode.dart';
import 'package:claudart/pipeline/tool_grant.dart';
import 'package:claudart/pipeline/step_result.dart';
import 'package:claudart/pipeline/usage.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';

// ── Case labels ────────────────────────────────────────────────────────────
// Named per PARADIGMS.md's "no bare strings" rule — every printed label
// lives on a top-level const, not inline in the _report() call site.
const _caseCliSurface = 'cli — config.surface';
const _caseCliBuildType = 'cli — build() runtimeType';
const _caseCliRunnerCalls = 'cli — injected runner call count';
const _caseCliRunnerResult = 'cli — step result stored in ctx';
const _caseCliStrictTrue = 'cli — strict: true  → build().strict';
const _caseCliStrictFalse = 'cli — strict: false → build().strict';
const _caseTuiSurface = 'tui — config.surface';
const _caseTuiBuildType = 'tui (no approvalSelector) — build() runtimeType';
const _caseTuiRunnerCalls = 'tui — injected runner call count';
const _caseTuiRunnerResult = 'tui — step result stored in ctx';
const _caseTuiStrictTrue = 'tui — strict: true  → build().strict';
const _caseTuiStrictFalse = 'tui — strict: false → build().strict';

void _report(String caseLabel, Object? observed) =>
    print('  [claudart_surface] $caseLabel → $observed');

PipelineContext _ctx() => const PipelineContext(
      projectRoot: _projectRoot,
      bug: '',
      expected: '',
      files: [],
    );

AgentStep _echoStep({required String id}) => AgentStep(
      id: id,
      label: 'Step $id',
      model: AgentModel.haiku,
      systemPrompt: 'sys',
      buildPrompt: (_) => 'msg',
    );

void main() {
  group('SurfaceExecutorConfig.cli', () {
    test('declares ClaudartSurface.cli', () {
      final config = SurfaceExecutorConfig.cli();
      _report(_caseCliSurface, config.surface);
      expect(config.surface, equals(ClaudartSurface.cli));
    });

    test('builds a PipelineExecutor', () {
      final config = SurfaceExecutorConfig.cli();
      final built = config.build();
      _report(_caseCliBuildType, built.runtimeType);
      expect(built, isA<PipelineExecutor>());
    });

    test('wires the injected runner through to the built executor', () async {
      var calls = 0;
      final config = SurfaceExecutorConfig.cli(
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async {
          calls++;
          return const StepResult(
            text: 'from injected runner',
            usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
          );
        },
      );

      final ctx = await config.build().runFuture(
        steps: [_echoStep(id: 'a')],
        ctx: _ctx(),
        displayStep: 1,
        displayTotal: 1,
      );

      _report(_caseCliRunnerCalls, calls);
      _report(_caseCliRunnerResult, ctx['a']);
      expect(calls, equals(1));
      expect(ctx['a'], equals('from injected runner'));
    });

    test('wires strict through to the built executor', () {
      final strictTrue = SurfaceExecutorConfig.cli(strict: true).build().strict;
      final strictFalse =
          SurfaceExecutorConfig.cli(strict: false).build().strict;
      _report(_caseCliStrictTrue, strictTrue);
      _report(_caseCliStrictFalse, strictFalse);
      expect(strictTrue, isTrue);
      expect(strictFalse, isFalse);
    });
  });

  group('SurfaceExecutorConfig.tui', () {
    test('declares ClaudartSurface.tui', () {
      final config = SurfaceExecutorConfig.tui(prompter: (_) async => '');
      _report(_caseTuiSurface, config.surface);
      expect(config.surface, equals(ClaudartSurface.tui));
    });

    test('builds without an approvalSelector', () {
      final config = SurfaceExecutorConfig.tui(prompter: (_) async => '');
      final built = config.build();
      _report(_caseTuiBuildType, built.runtimeType);
      expect(built, isA<PipelineExecutor>());
    });

    test('wires the injected runner through to the built executor', () async {
      var calls = 0;
      final config = SurfaceExecutorConfig.tui(
        prompter: (_) async => '',
        runner: ({
          required model,
          required systemPrompt,
          required message,
          required workingDir,
          StepMode mode = StepMode.project,
          ToolGrant toolGrant = ToolGrant.readOnly,
        }) async {
          calls++;
          return const StepResult(
            text: 'from injected runner',
            usage: Usage(input: 1, output: 1, cacheRead: 0, cost: 0),
          );
        },
      );

      final ctx = await config.build().runFuture(
        steps: [_echoStep(id: 'a')],
        ctx: _ctx(),
        displayStep: 1,
        displayTotal: 1,
      );

      _report(_caseTuiRunnerCalls, calls);
      _report(_caseTuiRunnerResult, ctx['a']);
      expect(calls, equals(1));
      expect(ctx['a'], equals('from injected runner'));
    });

    test('wires strict through to the built executor', () {
      final strictTrue = SurfaceExecutorConfig.tui(
        prompter: (_) async => '',
        strict: true,
      ).build().strict;
      final strictFalse = SurfaceExecutorConfig.tui(
        prompter: (_) async => '',
        strict: false,
      ).build().strict;
      _report(_caseTuiStrictTrue, strictTrue);
      _report(_caseTuiStrictFalse, strictFalse);
      expect(strictTrue, isTrue);
      expect(strictFalse, isFalse);
    });
  });
}
