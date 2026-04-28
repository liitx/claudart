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
import '../ui/menu.dart';
import 'agent_model.dart';
import 'agent_step.dart';
import 'pipeline_context.dart';
import 'pipeline_event.dart';
import 'step_route.dart';
import 'usage.dart';
import 'xml_tags.dart';

// ── Injectable types ──────────────────────────────────────────────────────────

typedef ClaudeRunner = Future<({String text, Usage usage})?> Function({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
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
  })  : _runner           = runner           ?? _defaultClaudeRunner,
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
      yield AgentStarted(
        stepId:       current.id,
        label:        current.label,
        model:        current.model,
        displayStep:  displayStep,
        displayTotal: displayTotal,
      );

      final result = await _runner(
        model:        current.model,
        systemPrompt: current.systemPrompt,
        message:      current.buildPrompt(ctx),
        workingDir:   ctx.projectRoot,
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

      // Find first matching tag → route.
      String?    matchedTag;
      StepRoute? route;
      for (final entry in current.routes.entries) {
        if (tagOrNull(result.text, entry.key) != null) {
          matchedTag = entry.key;
          route      = entry.value;
          break;
        }
      }

      if (route == null) {
        // strict: if routes were declared but none matched, escalate rather
        // than silently falling through — agent output violated its schema.
        if (strict && current.routes.isNotEmpty) {
          final expected = current.routes.keys.map((t) => '<$t>').join(', ');
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
          final question = tagOrNull(result.text, matchedTag!)!;
          ctx     = ctx.withSlot(PipelineSlot.question, question);
          current = stepMap[lookupStepId]!;

        case FeedBackTo(:final stepId):
          final answer = tagOrNull(result.text, matchedTag!)!;
          ctx     = ctx.appendClarification('Codebase lookup: $answer');
          current = stepMap[stepId]!;

        case EscalateUser(:final returnToStepId):
          final unknown  = tagOrNull(result.text, matchedTag!);
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
          final plan = tagOrNull(result.text, planTag) ?? result.text;
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

    void stopSpinner({required bool success, String? stats}) {
      spinnerTimer?.cancel();
      spinnerTimer = null;
      final icon    = success ? '${ansi.green}✓' : '${ansi.red}✗';
      final statStr = stats != null ? '  ${ansi.dim}$stats${ansi.reset}' : '';
      stdout.write('\x1B[2K\r  $icon${ansi.reset}  $stepTag  $stepLabel$statStr\n');
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

        case AgentCompleted(:final usage):
          stopSpinner(success: true, stats: usage.format());

        case AgentFailed():
          stopSpinner(success: false);

        case AgentEscalating(:final unknownContext):
          // Stop spinner before prompting; _prompter prints 'Answer: ' itself.
          stopSpinner(success: true);
          if (unknownContext != null) {
            print('\n  ${ansi.dim}  Not in files: $unknownContext${ansi.reset}\n');
          }

        case AgentResumed():
          break; // Next AgentStarted restarts the spinner.

        case PlanDraft(:final plan):
          stopSpinner(success: true);
          print('\n$plan\n');

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

File? get _diagLog {
  final env = Platform.environment;
  if (env['CLAUDART_DIAG'] != '1') return null;
  final path = env['CLAUDART_DIAG_PATH'] ?? '/tmp/claudart_diag.log';
  return File(path);
}

Future<({String text, Usage usage})?> _defaultClaudeRunner({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
}) async {
  final ts  = DateTime.now().toIso8601String();
  final log = _diagLog;
  log?.writeAsStringSync(
    '[$ts] STEP: ${model.alias}  workingDir: $workingDir\n'
    '--- SYSTEM PROMPT ---\n$systemPrompt\n'
    '--- MESSAGE (first 2000 chars) ---\n${message.substring(0, message.length.clamp(0, 2000))}\n'
    '--- END INPUT ---\n\n',
    mode: FileMode.append,
  );

  try {
    final process = await Process.start(
      'claude',
      [
        '--print',
        '--verbose',
        '--output-format',            'stream-json',
        '--include-partial-messages',
        '--model',         model.alias,
        '--system-prompt', systemPrompt,
        '--dangerously-skip-permissions',
      ],
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
      log?.writeAsStringSync('[$ts] STREAM: $line\n', mode: FileMode.append);
    }

    final err  = await process.stderr.transform(const Utf8Decoder()).join();
    final code = await process.exitCode;
    log?.writeAsStringSync(
      '[$ts] EXIT: $code  stderr: ${err.trim().isEmpty ? "(none)" : err.trim()}\n\n',
      mode: FileMode.append,
    );

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
      input:     (raw['input_tokens']            as int?)    ?? 0,
      output:    (raw['output_tokens']           as int?)    ?? 0,
      cacheRead: (raw['cache_read_input_tokens'] as int?)    ?? 0,
      cost:      (json['total_cost_usd']         as num?)?.toDouble() ?? 0,
    );
    return (text: text, usage: usage);
  } on Exception catch (e) {
    log?.writeAsStringSync('[$ts] EXCEPTION: $e\n\n', mode: FileMode.append);
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
