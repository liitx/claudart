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

import '../config.dart' show defaultStepTimeout;
import '../process_runner.dart' show killProcessTree;
import '../providers/agent_provider.dart' show AgentProvider;
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
import 'step_mode.dart';
import 'step_result.dart';
import 'step_route.dart';
import 'usage.dart';
import 'xml_tags.dart';

// ── Injectable types ──────────────────────────────────────────────────────────

typedef ClaudeRunner = Future<StepResult?> Function({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
  StepMode mode,
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

  /// When true, [runFuture] prints a dim trace line for pipeline-internal
  /// events not otherwise visible to the user (e.g. a postProcess rewrite).
  /// [run] itself never does this IO — see this file's header: direct
  /// `run()` subscribers (e.g. zedup's UI) get no stdout side-effects
  /// regardless of this flag. It only reaches [AgentCompleted.postProcessRewrote],
  /// which [runFuture] reads to decide whether to print.
  final bool verbose;

  PipelineExecutor({
    ClaudeRunner?     runner,
    UserPrompter?     prompter,
    ApprovalSelector? approvalSelector,
    this.strict  = false,
    this.verbose = false,
    Duration? stepTimeout = defaultStepTimeout,
  })  : _runner           = runner           ?? _runnerWithTimeout(stepTimeout),
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
    // Tracks which step ids have already run this pipeline call, so a
    // routing loop-back (FeedBackTo, EscalateUser returning to the step
    // that asked) is distinguishable from ordinary forward advance —
    // AgentStarted.isRevisit is the graph-cycle signal a subscriber needs
    // to render the step sequence as a graph, not just a flat list.
    final visited = <String>{};

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
      final isRevisit = visited.contains(current.id);
      visited.add(current.id);
      yield AgentStarted(
        stepId:       current.id,
        label:        current.label,
        model:        stepModel,
        displayStep:  displayStep + localIndex,
        displayTotal: displayTotal,
        isRevisit:    isRevisit,
      );

      String? failureReason;
      StepResult? result;
      try {
        result = await _runner(
          model:        stepModel,
          systemPrompt: current.systemPrompt,
          message:      current.buildPrompt(ctx),
          workingDir:   ctx.projectRoot,
          mode:         current.mode,
        );
      } on Exception catch (e) {
        failureReason = e.toString();
      }

      if (result == null) {
        yield AgentFailed(stepId: current.id, reason: failureReason);
        yield PipelineCompleted(ctx: ctx);
        return;
      }

      final rawText = result.text;
      final stored = current.postProcess != null
          ? current.postProcess!(rawText, ctx)
          : rawText;
      final rewrote = current.postProcess != null && stored != rawText;
      ctx = ctx
          .withUsage(ctx.usage + result.usage)
          .withSlot(current.id, stored);

      yield AgentCompleted(
        stepId: current.id,
        usage: result.usage,
        postProcessRewrote: rewrote,
        thinking: result.thinking,
        stopReason: result.stopReason,
        durationMs: result.durationMs,
        numTurns: result.numTurns,
      );

      // Find first matching tag → route. `matchedTag` is typed
      // [RouteTag] so downstream extractions read `.wireTag` once and
      // pass the wire string to `tagOrNull`. Uses `stored` (post-processed
      // text) so postProcess can inject tags to correct malformed output.
      RouteTag?  matchedTag;
      StepRoute? route;
      for (final entry in current.routes.entries) {
        if (tagOrNull(stored, entry.key.wireTag) != null) {
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
            stepId: current.id,
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
          yield AgentResumed(stepId: current.id);
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
          final question = tagOrNull(stored, matchedTag!.wireTag)!;
          ctx     = ctx.withSlot(PipelineSlot.question, question);
          current = stepMap[lookupStepId]!;

        case FeedBackTo(:final stepId):
          final answer = tagOrNull(stored, matchedTag!.wireTag)!;
          ctx     = ctx.appendClarification('Codebase lookup: $answer');
          current = stepMap[stepId]!;

        case EscalateUser(:final returnToStepId):
          final unknown  = tagOrNull(stored, matchedTag!.wireTag);
          final question = ctx[PipelineSlot.question] ?? '';
          yield AgentEscalating(
            stepId:         current.id,
            question:       question,
            unknownContext: (unknown != null && unknown.isNotEmpty) ? unknown : null,
          );
          final answer = await _prompter(question);
          if (answer.isNotEmpty) {
            ctx = ctx.appendClarification('Clarification: $answer');
          }
          yield AgentResumed(stepId: current.id);
          current = stepMap[returnToStepId]!;

        case ApprovalGate(:final planTag, :final nextStepId):
          final plan =
              tagOrNull(stored, planTag.wireTag) ?? stored;
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
            yield AgentResumed(stepId: current.id);
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

    // Renders the typed colored block for a subagent-lifecycle event.
    // Shared by AgentCompleted/AgentFailed/AgentEscalating — same
    // rendering, different fields per event. Callers must clearSpinner()
    // themselves first — this doesn't, so a caller that needs to print
    // something else (the verbose trace line) between "spinner cleared"
    // and "block rendered" can do so without a second clear in between.
    void renderSubagentEvent(PipelineEvent event) {
      final response =
          toResponse(event, speaker: Speaker.subagent, workspace: wsLabel);
      if (response != null) print('${render.render(response)}\n');
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

        case AgentCompleted(:final stepId, :final postProcessRewrote):
          // clearSpinner first: print() moves the cursor to a new line, so
          // printing the trace before clearing would leave clearSpinner
          // erasing that new line instead of the spinner's — an artifact
          // left behind in the output.
          clearSpinner();
          if (verbose && postProcessRewrote) {
            print('  ${ansi.dim}◦ postProcess fired on "$stepId" — output rewritten${ansi.reset}');
          }
          renderSubagentEvent(event);

        case AgentFailed():
        case AgentEscalating():
          clearSpinner();
          renderSubagentEvent(event);

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

/// The `event.type` values inside a `stream_event` line that
/// `_accumulateThinking` cares about. Typed rather than matched as bare
/// strings — claudart's own `bare_string_for_enum` lint (dartrix
/// PARADIGMS.md) forbids exactly that dispatch shape.
enum _StreamEventType {
  contentBlockDelta('content_block_delta'),
  messageDelta('message_delta');

  const _StreamEventType(this.wire);

  /// The literal value the claude CLI emits for `event.type`.
  final String wire;

  static _StreamEventType? fromWire(String? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Casts [value] to a JSON object map, or `null` when it isn't one — a
/// successfully-decoded JSON value is not necessarily an object (`null`,
/// an array, a bare string/number all decode without error), so every
/// object-shaped access below goes through this instead of `as Map<...>`,
/// which throws (uncaught `TypeError`, not `FormatException`) on those
/// valid-but-wrong-shape values.
Map<String, dynamic>? _asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Casts [value] to a [String], or `null` when it isn't one — same
/// wrong-shape-throws-TypeError reasoning as [_asJsonMap], for scalar
/// fields read off a decoded JSON object.
String? _asJsonString(Object? value) => value is String ? value : null;

/// Parses one line of `--output-format stream-json --include-partial-messages`
/// output for extended-thinking content. Two things only live in the stream,
/// never on the final `"type":"result"` line: the thinking text itself
/// (`content_block_delta` events with a `thinking_delta`) and its token
/// count (the `message_delta` event's `usage.output_tokens_details
/// .thinking_tokens`). Malformed or irrelevant lines are silently ignored —
/// this is best-effort enrichment, not required for the step to succeed —
/// including lines that are valid JSON but not the object shape expected
/// at any level (a bare `null`, an array, a scalar).
void _accumulateThinking(
  String line,
  StringBuffer thinkingBuffer,
  void Function(int) onThinkingTokens,
) {
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return;
  }
  final json = _asJsonMap(decoded);
  if (json == null) return;
  if (json['type'] != 'stream_event') return;
  final event = _asJsonMap(json['event']);
  if (event == null) return;

  switch (_StreamEventType.fromWire(_asJsonString(event['type']))) {
    case _StreamEventType.contentBlockDelta:
      final delta = _asJsonMap(event['delta']);
      if (delta?['type'] == 'thinking_delta') {
        thinkingBuffer.write(_asJsonString(delta!['thinking']) ?? '');
      }
    case _StreamEventType.messageDelta:
      final usage = _asJsonMap(event['usage']);
      final details = _asJsonMap(usage?['output_tokens_details']);
      final tokens = details?['thinking_tokens'];
      if (tokens is int) onThinkingTokens(tokens);
    case null:
      // Every other stream_event subtype (message_start, content_block_start
      // /stop, message_stop, ...) — nothing this helper needs.
      break;
  }
}

/// Result of consuming a `claude` subprocess's stdout stream: every line
/// seen (for locating the final `"type":"result"` line) plus whatever
/// [_accumulateThinking] extracted along the way. Split out from
/// [defaultClaudeRunner] so the stream-parsing behavior — thinking-token
/// accumulation, in particular — can be exercised in a test against a
/// plain [Stream<String>] without spawning a real `claude` process.
class ClaudeStreamResult {
  final List<String> lines;
  final String? thinking;
  final int thinkingTokens;

  const ClaudeStreamResult({
    required this.lines,
    required this.thinking,
    required this.thinkingTokens,
  });
}

Future<ClaudeStreamResult> consumeClaudeStream(
  Stream<String> lines,
  StepDebugTrace trace,
) async {
  final collected = <String>[];
  final thinkingBuffer = StringBuffer();
  var thinkingTokens = 0;
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    collected.add(line);
    trace.writeStreamLine(line);
    _accumulateThinking(line, thinkingBuffer, (t) => thinkingTokens = t);
  }
  return ClaudeStreamResult(
    lines: collected,
    thinking: thinkingBuffer.isEmpty ? null : thinkingBuffer.toString(),
    thinkingTokens: thinkingTokens,
  );
}

/// Parses the final `"type":"result"` line of a `claude` stream into a
/// [StepResult], combining it with the thinking text/token count already
/// accumulated from earlier stream lines by [consumeClaudeStream]. Split
/// out from [defaultClaudeRunner] so `stop_reason`/`duration_ms`/`num_turns`
/// extraction can be tested directly against a real result-line string,
/// without spawning a `claude` subprocess.
StepResult parseClaudeResultLine(
  String resultLine, {
  required String? thinkingBuffer,
  required int thinkingTokens,
}) {
  final json  = jsonDecode(resultLine) as Map<String, dynamic>;
  final text  = (json['result'] as String?) ?? '';
  final raw   = json['usage']   as Map<String, dynamic>? ?? {};
  final usage = Usage(
    input:         (raw['input_tokens']                as int?) ?? 0,
    output:        (raw['output_tokens']               as int?) ?? 0,
    cacheRead:     (raw['cache_read_input_tokens']     as int?) ?? 0,
    cacheCreation: (raw['cache_creation_input_tokens'] as int?) ?? 0,
    cost: (json['total_cost_usd'] as num?)?.toDouble() ?? 0,
    thinkingTokens: thinkingTokens,
  );
  return StepResult(
    text: text,
    usage: usage,
    thinking: thinkingBuffer,
    stopReason: json['stop_reason'] as String?,
    durationMs: json['duration_ms'] as int?,
    numTurns: json['num_turns'] as int?,
  );
}

/// The default runner bound to a per-step [timeout] (`null` = no limit). A
/// closure, so the public [ClaudeRunner] typedef stays exactly as it was.
ClaudeRunner _runnerWithTimeout(Duration? timeout) => ({
      required AgentModel model,
      required String systemPrompt,
      required String message,
      required String workingDir,
      StepMode mode = StepMode.project,
    }) =>
        defaultClaudeRunner(
          model: model,
          systemPrompt: systemPrompt,
          message: message,
          workingDir: workingDir,
          mode: mode,
          timeout: timeout,
        );

String _describeDuration(Duration d) {
  if (d.inMinutes >= 1 && d.inSeconds % 60 == 0) {
    final m = d.inMinutes;
    return m == 1 ? '1 minute' : '$m minutes';
  }
  final s = d.inSeconds;
  return s == 1 ? '1 second' : '$s seconds';
}

/// Runs one `claude` step.
///
/// [timeout] is a per-step backstop (default [defaultStepTimeout], `null` = no
/// limit): if the subprocess has not finished by then, its whole process tree
/// is killed and the step fails with an [Exception], the same type as the
/// non-zero-exit failure below, so every caller's error handling applies
/// unchanged. The step id is attached by the executor's `AgentFailed` event.
/// [executable] and [traceOverride] are seams for tests.
Future<StepResult?> defaultClaudeRunner({
  required AgentModel model,
  required String systemPrompt,
  required String message,
  required String workingDir,
  StepMode mode = StepMode.project,
  Duration? timeout = defaultStepTimeout,
  String executable = 'claude',
  StepDebugTrace? traceOverride,
  AgentProvider? Function() providerDetector = AgentProvider.detectEffective,
}) async {
  // Fails fast with a clear message instead of letting an unconfigured
  // environment reach a mid-pipeline 401 from the `claude` subprocess
  // itself — see portability_gap.dart's providerWiring entry this closes.
  if (providerDetector() == null) {
    throw Exception(
      'No agent provider configured (checked ANTHROPIC_API_KEY, Bedrock '
      'env vars, and ~/.claude/settings.json). Run `claudart doctor` to diagnose.',
    );
  }

  // `StepDebugTrace.start()` resolves the log file via `debugLogFile()`.
  // When debug mode is off, every `trace.write*` below is a no-op.
  // When on, writes are best-effort — IOException swallows so an
  // unwritable log path never aborts a real pipeline run.
  final trace = traceOverride ?? StepDebugTrace.start();
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
      executable,
      [
        '--print',
        '--verbose',
        '--output-format',            'stream-json',
        '--include-partial-messages',
        '--session-id',    newClaudeSessionId(),
        '--model',         model.alias,
        '--system-prompt', systemPrompt,
        '--dangerously-skip-permissions',
        if (mode == StepMode.bare) '--bare',
      ],
      workingDirectory: workingDir,
    );
    process.stdin.writeln(message);
    await process.stdin.close();

    // Extended-thinking text arrives incrementally as `thinking_delta`
    // stream events, not on the final result line — only the final
    // answer text is repeated there. Accumulated here as the stream is
    // consumed rather than re-parsed afterward.
    //
    // Everything from here to the exit code is one span, so a hung step is
    // bounded by [timeout] as a whole.
    Future<({ClaudeStreamResult stream, String err, int code})> consume() async {
      final stream = await consumeClaudeStream(
        process.stdout.transform(const Utf8Decoder()).transform(const LineSplitter()),
        trace,
      );
      final err  = await process.stderr.transform(const Utf8Decoder()).join();
      final code = await process.exitCode;
      return (stream: stream, err: err, code: code);
    }

    final ({ClaudeStreamResult stream, String err, int code}) outcome;
    try {
      outcome = timeout == null ? await consume() : await consume().timeout(timeout);
    } on TimeoutException {
      // The whole tree, not just the direct child: `claude` can be waiting on
      // a helper (for example a credential process) that would otherwise be
      // orphaned and keep running.
      await killProcessTree(process.pid);
      process.kill(ProcessSignal.sigkill);
      final killedCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      final after = _describeDuration(timeout!);
      trace.writeExit(
        exitCode: killedCode,
        stderrText: 'TIMED OUT after $after (stepTimeoutMinutes); killed the whole process tree',
      );
      throw Exception(
        'claude step timed out after $after and was killed. '
        'Raise or disable (0) "stepTimeoutMinutes" in the workspace config.json.',
      );
    }
    final lines = outcome.stream.lines;
    final thinkingBuffer = outcome.stream.thinking;
    final thinkingTokens = outcome.stream.thinkingTokens;
    final err  = outcome.err;
    final code = outcome.code;
    trace.writeExit(exitCode: code, stderrText: err);

    if (code != 0) {
      if (err.trim().isNotEmpty) stderr.writeln(err.trim());
      throw Exception(
        'claude exited $code${err.trim().isEmpty ? '' : ': ${err.trim()}'}',
      );
    }

    final resultLine = lines.lastWhere(
      (l) => l.contains('"type":"result"'),
      orElse: () => '',
    );
    if (resultLine.isEmpty) {
      throw Exception('claude produced no result line');
    }

    final result = parseClaudeResultLine(
      resultLine,
      thinkingBuffer: thinkingBuffer,
      thinkingTokens: thinkingTokens,
    );
    trace.writeSummary(
      modelAlias: model.alias,
      systemPrompt: systemPrompt,
      message: message,
      input: result.usage.input,
      cacheRead: result.usage.cacheRead,
      cacheCreation: result.usage.cacheCreation,
      output: result.usage.output,
      cost: result.usage.cost,
      resultText: result.text,
    );
    return result;
  } on Exception catch (e) {
    trace.writeException(e);
    stderr.writeln('claude call failed: $e');
    rethrow;
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
