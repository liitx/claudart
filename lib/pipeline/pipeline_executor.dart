// pipeline_executor.dart — stream-driven agent pipeline engine
//
// PipelineExecutor.run() returns Stream<PipelineEvent>. Each event maps to a
// transition in the pipeline FSM (see pipeline_event.dart for the δ table).
//
// Callers:
//   CLI commands    → use runFuture(), which subscribes to run() and renders
//                     spinners + prompts, then returns the final PipelineContext.
//   zedup UI        → subscribe to run() directly; render Agents Workflow pane
//                     from events without any stdout side-effects.
//
// Testability:
//   Inject [ClaudeRunner] to capture calls without spawning real processes.
//   Inject [UserPrompter] to supply answers without stdin.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import 'debug_mode.dart';
import '../ui/menu.dart';
import 'agent_model.dart';
import 'agent_response.dart';
import 'agent_step.dart';
import 'claude_session.dart';
import 'event_response_map.dart';
import 'pipeline_context.dart';
import 'pipeline_event.dart';
import 'route_tag.dart';
import 'step_route.dart';
import 'usage.dart';
import 'xml_tags.dart';

// ── Injectable types ──────────────────────────────────────────────────────────

typedef ClaudeRunner = Future<({String text, Usage usage})?> Function({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
  required ToolGrant toolGrant,
});

typedef UserPrompter     = Future<String> Function(String question);
typedef ApprovalSelector = Future<int>   Function(List<String> options);

// ── PipelineExecutor ──────────────────────────────────────────────────────────

class PipelineExecutor {
  final ClaudeRunner    _runner;
  final UserPrompter    _prompter;
  final ApprovalSelector _approvalSelector;
  /// When true (set via WorkspaceOwner.strict), every step output is validated
  /// against its declared route tags. A step with routes but no matching tag
  /// escalates to the user instead of silently falling through.
  final bool strict;

  PipelineExecutor({
    ClaudeRunner?     runner,
    UserPrompter?     prompter,
    ApprovalSelector? approvalSelector,
    this.strict = false,
  })  : _runner           = runner           ?? defaultClaudeRunner,
        _prompter         = prompter         ?? _defaultPrompter,
        _approvalSelector = approvalSelector ?? _defaultApprovalSelector;

  /// Runs [steps] and emits [PipelineEvent]s for each lifecycle transition.
  ///
  /// Begins at steps[0]. Routes drive the next step; absence of a matching
  /// route falls through to the next step, or emits [PipelineCompleted] if
  /// steps are exhausted. Always terminates with [PipelineCompleted].
  ///
  /// [displayStep] / [displayTotal] are forwarded in [AgentStarted] so
  /// subscribers can render `[n/N]` labels without tracking call order.
  Stream<PipelineEvent> run({
    required List<AgentStep> steps,
    required PipelineContext ctx,
    required int displayStep,
    required int displayTotal,
  }) async* {
    if (steps.isEmpty) {
      yield PipelineCompleted(ctx: ctx);
      return;
    }

    final stepMap = {for (final s in steps) s.id: s};
    var current   = steps.first;

    while (true) {
      // Local position within `steps` so the same `run` call advances
      // through `[1/N], [2/N], …` without the caller tracking it.
      // `displayStep` is the base offset, useful when this run is one
      // phase of a larger flow (e.g. resuming from checkpoint).
      final localIndex = steps.indexOf(current);
      // Resolve once per step so the AgentStarted event and the runner
      // call agree on which model fired. modelSelector can read ctx
      // (e.g. plan step reads categorize output for ComplexityTier).
      final stepModel = current.effectiveModel(ctx);
      yield AgentStarted(
        stepId:       current.id,
        label:        current.label,
        model:        stepModel,
        displayStep:  displayStep + localIndex,
        displayTotal: displayTotal,
      );

      final result = await _runner(
        model:        stepModel,
        systemPrompt: current.systemPrompt,
        message:      current.buildPrompt(ctx),
        workingDir:   ctx.projectRoot,
        toolGrant:    current.toolGrant,
      );

      if (result == null) {
        yield AgentFailed(stepId: current.id);
        yield PipelineCompleted(ctx: ctx);
        return;
      }

      ctx = ctx
          .withUsage(ctx.usage + result.usage)
          .withSlot(current.id, result.text);

      yield AgentCompleted(stepId: current.id, usage: result.usage);

      // Find first matching tag → route. `matchedTag` is typed
      // [RouteTag] so downstream extractions read `.wireTag` once and
      // pass the wire string to `tagOrNull`.
      RouteTag?  matchedTag;
      StepRoute? route;
      for (final entry in current.routes.entries) {
        if (tagOrNull(result.text, entry.key.wireTag) != null) {
          matchedTag = entry.key;
          route      = entry.value;
          break;
        }
      }

      if (route == null) {
        // strict: if routes were declared but none matched, escalate rather
        // than silently falling through — agent output violated its schema.
        if (strict && current.routes.isNotEmpty) {
          final expected =
              current.routes.keys.map((t) => '<${t.wireTag}>').join(', ');
          yield AgentEscalating(
            question:
                'Step "${current.id}" produced no recognised tag.\n'
                '  Expected one of: $expected\n'
                '  Continue anyway? [y to proceed / n to abort]',
          );
          final answer = await _prompter('');
          if (!answer.toLowerCase().startsWith('y')) {
            yield PipelineCompleted(ctx: ctx);
            return;
          }
          yield const AgentResumed();
        }
        final idx = steps.indexOf(current);
        if (idx < steps.length - 1) {
          current = steps[idx + 1];
          continue;
        }
        yield PipelineCompleted(ctx: ctx);
        return;
      }

      switch (route) {
        case GoTo(:final stepId):
          current = stepMap[stepId]!;

        case QuestionBranch(:final lookupStepId):
          final question = tagOrNull(result.text, matchedTag!.wireTag)!;
          ctx     = ctx.withSlot(PipelineSlot.question, question);
          current = stepMap[lookupStepId]!;

        case FeedBackTo(:final stepId):
          final answer = tagOrNull(result.text, matchedTag!.wireTag)!;
          ctx     = ctx.appendClarification('Codebase lookup: $answer');
          current = stepMap[stepId]!;

        case EscalateUser(:final returnToStepId):
          final unknown  = tagOrNull(result.text, matchedTag!.wireTag);
          final question = ctx[PipelineSlot.question] ?? '';
          yield AgentEscalating(
            question:       question,
            unknownContext: (unknown != null && unknown.isNotEmpty) ? unknown : null,
          );
          final answer = await _prompter(question);
          if (answer.isNotEmpty) {
            ctx = ctx.appendClarification('Clarification: $answer');
          }
          yield const AgentResumed();
          current = stepMap[returnToStepId]!;

        case ApprovalGate(:final planTag, :final nextStepId):
          final plan =
              tagOrNull(result.text, planTag.wireTag) ?? result.text;
          yield PlanDraft(plan: plan);
          yield const AwaitingApproval();

          final choice = await _approvalSelector([
            'approve',
            'refine  ${ansi.dim}(add feedback · re-plan)${ansi.reset}',
            'exit  ${ansi.dim}(save checkpoint · resume later)${ansi.reset}',
          ]);

          if (choice == 2) {
            ctx = ctx.withSlot(PipelineSlot.flowExit, 'true');
            yield PipelineCompleted(ctx: ctx);
            return;
          }

          if (choice == 1) {
            final feedback = await _prompter('  Refinement');
            if (feedback.isNotEmpty) {
              ctx = ctx.appendClarification('Refinement: $feedback');
            }
            yield const AgentResumed();
            // loop back to plan step; fall through to approve if plan not in this run
            final planStep = stepMap['plan'];
            if (planStep != null) {
              current = planStep;
            } else {
              ctx = ctx.withSlot(PipelineSlot.approved, 'true');
              yield PipelineCompleted(ctx: ctx);
              return;
            }
          } else {
            // choice == 0: approve
            final nextStep = stepMap[nextStepId];
            if (nextStep != null) {
              current = nextStep;
            } else {
              ctx = ctx.withSlot(PipelineSlot.approved, 'true');
              yield PipelineCompleted(ctx: ctx);
              return;
            }
          }

        case Complete():
          yield PipelineCompleted(ctx: ctx);
          return;
      }
    }
  }

  /// Convenience wrapper for CLI callers that need only the final context.
  ///
  /// Subscribes to [run], renders spinner and prompt output to stdout,
  /// and returns the [PipelineContext] from [PipelineCompleted].
  /// Existing callers of the previous Future-based `run()` migrate here
  /// with no behavior change.
  Future<PipelineContext> runFuture({
    required List<AgentStep> steps,
    required PipelineContext ctx,
    required int displayStep,
    required int displayTotal,
  }) async {
    PipelineContext result = ctx;
    final wsLabel = ctx.projectRoot.split('/').last;

    // Mutable spinner state — local to this subscription.
    Timer? spinnerTimer;
    var    spinnerIdx = 0;
    const  frames     = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    var    stepLabel  = '';
    var    stepTag    = '';

    void startSpinner(String label, int step, int total) {
      stepLabel = label;
      stepTag   = '${ansi.dim}[$step/$total]${ansi.reset}';
      spinnerIdx = 0;
      stdout.write('  ${ansi.cyan}${frames[0]}${ansi.reset}  $stepTag  $stepLabel');
      spinnerTimer?.cancel();
      spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        spinnerIdx = (spinnerIdx + 1) % frames.length;
        stdout.write(
          '\x1B[2K\r  ${ansi.cyan}${frames[spinnerIdx]}${ansi.reset}  $stepTag  $stepLabel',
        );
      });
    }

    // Cancel the animated spinner and clear its line, leaving the cursor at
    // column 0 so the typed block for this event renders cleanly beneath it.
    void clearSpinner() {
      spinnerTimer?.cancel();
      spinnerTimer = null;
      stdout.write('\x1B[2K\r');
    }

    await for (final event in run(
      steps:        steps,
      ctx:          ctx,
      displayStep:  displayStep,
      displayTotal: displayTotal,
    )) {
      switch (event) {
        case AgentStarted(:final label, :final displayStep, :final displayTotal):
          startSpinner(label, displayStep, displayTotal);

        case AgentCompleted():
        case AgentFailed():
        case AgentEscalating():
          // Clear the spinner line, then render the typed colored block.
          clearSpinner();
          final response =
              toResponse(event, speaker: Speaker.subagent, workspace: wsLabel);
          if (response != null) print('${render.render(response)}\n');

        case AgentResumed():
          break; // Next AgentStarted restarts the spinner.

        case PlanDraft(:final plan):
          clearSpinner();
          print('\n${render.planDraft(plan)}\n');

        case AwaitingApproval():
          // _prompter is awaited inside the generator after this event.
          break;

        case PipelineCompleted(ctx: final completedCtx):
          result = completedCtx;
      }
    }

    spinnerTimer?.cancel();
    return result;
  }
}

// ── Standalone spinner (non-agent I/O steps, e.g. writing handoff) ────────────

Future<T?> runWithSpinner<T>({
  required String label,
  required int step,
  required int total,
  required Future<T?> Function() task,
  String Function(T)? stats,
}) async {
  const frames  = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  final stepTag = '${ansi.dim}[$step/$total]${ansi.reset}';
  var   idx     = 0;
  stdout.write('  ${ansi.cyan}${frames[0]}${ansi.reset}  $stepTag  $label');
  final timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
    idx = (idx + 1) % frames.length;
    stdout.write('\x1B[2K\r  ${ansi.cyan}${frames[idx]}${ansi.reset}  $stepTag  $label');
  });
  final result = await task();
  timer.cancel();
  final icon    = result != null ? '${ansi.green}✓' : '${ansi.red}✗';
  final statStr = result != null && stats != null
      ? '  ${ansi.dim}${stats(result)}${ansi.reset}'
      : '';
  stdout.write('\x1B[2K\r  $icon${ansi.reset}  $stepTag  $label$statStr\n');
  return result;
}

// ── Default ClaudeRunner ──────────────────────────────────────────────────────

/// Builds the `claude` CLI args for one step call. Pulled out of
/// [defaultClaudeRunner] so the grant a step gets is assertable without
/// spawning a real process. Every step is read-only today, so this always
/// grants [ToolGrant.tools] via `--allowedTools` and never
/// `--dangerously-skip-permissions` — add the skip flag here, gated on a
/// future non-read-only [ToolGrant] variant, the day one exists.
List<String> buildClaudeArgs({
  required AgentModel model,
  required String systemPrompt,
  required String sessionId,
  required ToolGrant toolGrant,
}) => [
  '--print',
  '--verbose',
  '--output-format',            'stream-json',
  '--include-partial-messages',
  '--session-id',    sessionId,
  '--model',         model.alias,
  '--system-prompt', systemPrompt,
  '--allowedTools',  toolGrant.tools.join(','),
];

Future<({String text, Usage usage})?> defaultClaudeRunner({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
  required ToolGrant toolGrant,
}) async {
  // `StepDebugTrace.start()` resolves the log file via `debugLogFile()`.
  // When debug mode is off, every `trace.write*` below is a no-op.
  // When on, writes are best-effort — IOException swallows so an
  // unwritable log path never aborts a real pipeline run.
  final trace = StepDebugTrace.start();
  trace.writeStepHeader(
    modelAlias: model.alias,
    workingDir: workingDir,
    systemPrompt: systemPrompt,
    message: message,
  );

  try {
    // Isolate by SESSION, not config: a unique --session-id gives this run its own
    // conversation, distinct from the user's interactive Claude Code session, while
    // keeping the live shared ~/.claude auth (config-dir isolation 401s — the OAuth
    // token rotates and a copied credential goes stale).
    final process = await Process.start(
      'claude',
      buildClaudeArgs(
        model:        model,
        systemPrompt: systemPrompt,
        sessionId:    newClaudeSessionId(),
        toolGrant:    toolGrant,
      ),
      workingDirectory: workingDir,
    );
    process.stdin.writeln(message);
    await process.stdin.close();

    final lines = <String>[];
    await for (final line in process.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      lines.add(line);
      trace.writeStreamLine(line);
    }

    final err  = await process.stderr.transform(const Utf8Decoder()).join();
    final code = await process.exitCode;
    trace.writeExit(exitCode: code, stderrText: err);

    if (code != 0) {
      if (err.trim().isNotEmpty) stderr.writeln(err.trim());
      return null;
    }

    final resultLine = lines.lastWhere(
      (l) => l.contains('"type":"result"'),
      orElse: () => '',
    );
    if (resultLine.isEmpty) return null;

    final json  = jsonDecode(resultLine) as Map<String, dynamic>;
    final text  = (json['result'] as String?) ?? '';
    final raw   = json['usage']   as Map<String, dynamic>? ?? {};
    final usage = Usage(
      input:         (raw['input_tokens']                as int?) ?? 0,
      output:        (raw['output_tokens']               as int?) ?? 0,
      cacheRead:     (raw['cache_read_input_tokens']     as int?) ?? 0,
      cacheCreation: (raw['cache_creation_input_tokens'] as int?) ?? 0,
      cost: (json['total_cost_usd'] as num?)?.toDouble() ?? 0,
    );
    trace.writeSummary(
      modelAlias: model.alias,
      systemPrompt: systemPrompt,
      message: message,
      input: usage.input,
      cacheRead: usage.cacheRead,
      cacheCreation: usage.cacheCreation,
      output: usage.output,
      cost: usage.cost,
      resultText: text,
    );
    return (text: text, usage: usage);
  } on Exception catch (e) {
    trace.writeException(e);
    stderr.writeln('claude call failed: $e');
    return null;
  }
}

// ── Default UserPrompter ──────────────────────────────────────────────────────

Future<String> _defaultPrompter(String question) async {
  if (question.isNotEmpty) {
    stdout.write('  Answer: ');
  }
  return stdin.readLineSync()?.trim() ?? '';
}

// ── Default ApprovalSelector ─────────────────────────────────────────────────

Future<int> _defaultApprovalSelector(List<String> options) async =>
    arrowMenu(options);
