// flow.dart — claudart flow command
//
// Opens an agent-constructed session. The user provides a freeform prompt;
// the pipeline classifies intent, generates a dependency-ordered plan, awaits
// approval, then constructs the handoff automatically.
//
// Differs from suggest: the agent builds the handoff, not the user.
// Experimental variant — treat as a preview feature.

import 'dart:convert';
import 'dart:io';
import '../file_io.dart';
import '../git_utils.dart';
import '../logging/planner_log.dart';
import '../paths.dart';
import '../pipeline/agents/categorization.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/route_tag.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../util/enum_util.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../ui/render.dart' as render;
import '../workspace/workspace_config.dart';

Future<void> runFlow({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
  PlannerLog? plannerLog,
  int Function(List<String> items)? pickFn,
}) async {
  final fileIO = io   ?? const RealFileIO();
  final exit_  = exitFn ?? exit;
  final planner = plannerLog ?? PlannerLog();
  final pick_  = pickFn ?? arrowMenu;

  // ── Locate project ─────────────────────────────────────────────────────────

  final projectRoot = projectRootOverride ?? detectGitContext()?.root;
  if (projectRoot == null) {
    print('✗ Not inside a git repository.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry    = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('✗ Project not registered. Run `claudart link` first.');
    exit_(1);
  }

  final workspace    = entry.workspacePath;
  final wsConfig     = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode   = wsConfig?.owner.strict ?? false;
  final resolvedExec = executor ?? PipelineExecutor(strict: strictMode);

  // ── Check for saved checkpoint ─────────────────────────────────────────────

  final checkpointPath = '$workspace/$flowCheckpointFileName';
  final checkpointFile = File(checkpointPath);

  if (checkpointFile.existsSync()) {
    print(render.header('CLAUDART FLOW  ${ansi.dim}[resume]${ansi.reset}'));
    print('  A saved checkpoint was found from a previous session.\n');

    try {
      final json    = jsonDecode(checkpointFile.readAsStringSync()) as Map<String, dynamic>;
      final savedCtx = PipelineContext.fromCheckpointJson(json);
      final savedPlan = savedCtx['plan'] ?? '';

      if (savedPlan.isNotEmpty) {
        print(savedPlan);
        print('');
      }

      final resumeChoice = pick_([
        'approve saved plan',
        'refine  ${ansi.dim}(add feedback · re-plan)${ansi.reset}',
        'exit  ${ansi.dim}(keep checkpoint · resume later)${ansi.reset}',
      ]);

      if (resumeChoice == 2) {
        print('\n  Checkpoint kept at:\n  ${ansi.dim}$checkpointPath${ansi.reset}\n');
        exit_(0);
      }

      if (resumeChoice == 0) {
        // Skip phases 1+2; go straight to construct with the saved plan.
        // The checkpoint is the only copy of the plan, so it is deleted
        // only after the handoff has actually been written.
        var ctx = savedCtx.withSlot(PipelineSlot.approved, 'true');
        ctx = await resolvedExec.runFuture(
          steps:        [FlowSteps.construct],
          ctx:          ctx,
          displayStep:  3,
          displayTotal: 3,
        );
        await _writeHandoff(ctx, workspace, fileIO, exit_);
        checkpointFile.deleteSync();
        return;
      }

      // refine: collect feedback, re-run phases 2+3 with saved context
      stdout.write('\n  Refinement: ');
      final feedback = stdin.readLineSync()?.trim() ?? '';
      var ctx = feedback.isNotEmpty
          ? savedCtx.appendClarification('Refinement: $feedback')
          : savedCtx;

      ctx = await _runPhase2(resolvedExec, ctx, checkpointPath, exit_);
      ctx = await resolvedExec.runFuture(
        steps:        [FlowSteps.construct],
        ctx:          ctx,
        displayStep:  3,
        displayTotal: 3,
      );
      await _writeHandoff(ctx, workspace, fileIO, exit_);
      checkpointFile.deleteSync();
      return;
    } on FormatException {
      print('  ${ansi.dim}Checkpoint unreadable — starting fresh.${ansi.reset}\n');
      checkpointFile.deleteSync();
    } on TypeError {
      print('  ${ansi.dim}Checkpoint unreadable — starting fresh.${ansi.reset}\n');
      checkpointFile.deleteSync();
    }
  }

  // ── Collect prompt ─────────────────────────────────────────────────────────

  print(render.header('CLAUDART FLOW  ${ansi.dim}[experimental]${ansi.reset}'));
  print(
    '  Enter your prompt. An agent will classify intent, generate a\n'
    '  dependency-ordered plan, and construct the handoff automatically.\n'
    '  ${ansi.dim}Type your task description and press enter.${ansi.reset}\n',
  );
  stdout.write('  → ');
  final prompt = stdin.readLineSync()?.trim() ?? '';
  if (prompt.isEmpty) {
    print('\n  No prompt entered. Aborted.\n');
    exit_(0);
  }

  // ── Pipeline ───────────────────────────────────────────────────────────────

  var ctx = PipelineContext(
    projectRoot: projectRoot,
    bug:         prompt,
    expected:    '',
    files:       [],
  );

  // Phase 1: categorize (haiku)
  ctx = await resolvedExec.runFuture(
    steps:        [FlowSteps.categorize],
    ctx:          ctx,
    displayStep:  1,
    displayTotal: 3,
  );

  // Display the LLM's actual classification (not a parallel regex
  // pre-classify) so the verdict the user sees is the one that
  // actually drives `_planModelSelector` downstream.
  _printClassification(ctx);

  // Record the planner's routing decision to ~/.claudart/planner.jsonl.
  // Skips silently when the categorize step's output is malformed —
  // logging never blocks the flow.
  _recordClassification(ctx, planner);

  // Phase 2: plan (sonnet) — approval gate (approve / refine / exit)
  ctx = await _runPhase2(resolvedExec, ctx, checkpointPath, exit_);

  // Phase 3: construct (sonnet)
  ctx = await resolvedExec.runFuture(
    steps:        [FlowSteps.construct],
    ctx:          ctx,
    displayStep:  3,
    displayTotal: 3,
  );

  await _writeHandoff(ctx, workspace, fileIO, exit_);
}

// ── Classification display ───────────────────────────────────────────────────

/// Prints the LLM's actual classification verdict to the terminal. Pulls
/// the three axes from `<CATEGORY>` / `<INTENT>` / `<COMPLEXITY>` in the
/// categorize step's output and routes them through `routeModel` — the
/// same path `_planModelSelector` consults — so the verdict the user sees
/// is the one that picks the plan-step model. No parallel regex
/// classifier, no display/routing divergence.
///
/// On malformed output (missing/unknown tag) the helper still emits a
/// single line so the user knows categorize ran but the verdict is
/// degraded; downstream `_planModelSelector` will fall back to sonnet.
void _printClassification(PipelineContext ctx) {
  final raw = ctx[PipelineSlot.categorize] ?? '';
  final category = enumByName(
    AgentCategory.values,
    CategorizeTag.category.extractFrom(raw),
  );
  final intent = enumByName(
    IntentClass.values,
    CategorizeTag.intent.extractFrom(raw),
  );
  final complexity = enumByName(
    ComplexityTier.values,
    CategorizeTag.complexity.extractFrom(raw),
  );
  if (category == null || intent == null || complexity == null) {
    print('${render.classification(degraded: true)}\n');
    return;
  }
  final routed = routeModel(category, intent, complexity);
  print(
    '${render.classification(
      category:   category.name,
      intent:     intent.name,
      complexity: complexity.name,
      model:      routed.shortName,
    )}\n',
  );
}

// ── Planner-log helper ────────────────────────────────────────────────────────

/// Parses the categorize step's output and appends one JSONL record to
/// the planner log. No-op when the output is malformed (missing tag or
/// unknown enum variant) — logging is best-effort, never blocks the flow.
///
/// I/O failures from [PlannerLog.record] (disk full, perms, missing
/// parent dir) are swallowed; the categorize step continues and a
/// single warning line is written to stderr. The warning string lives
/// on [plannerLogRecordFailureWarning] so production + tests share it.
void _recordClassification(PipelineContext ctx, PlannerLog planner) {
  final raw = ctx[PipelineSlot.categorize] ?? '';
  if (raw.isEmpty) return;
  // ScopeFile is a (relative, absolute) record. The path heuristic cares
  // about the relative path (which matches what test stubs assert against).
  final scopedPaths = ctx.files.map((f) => f.relative).toList();
  final decision = PlannerDecision.fromCategorizeOutput(
    raw,
    designSurfaceCounts: planner.tallySurfaces(scopedPaths),
  );
  if (decision == null) return;
  try {
    planner.record(decision);
  } on Exception {
    stderr.writeln(plannerLogRecordFailureWarning);
  }
}

// ── Phase 2 helper ────────────────────────────────────────────────────────────
//
// Runs plan+clarify steps. Returns the approved context, or null if the user
// chose exit (checkpoint already written) or the flow was otherwise aborted.

Future<PipelineContext> _runPhase2(
  PipelineExecutor exec,
  PipelineContext  ctx,
  String           checkpointPath,
  Never Function(int) exit_,
) async {
  final result = await exec.runFuture(
    steps:        [FlowSteps.plan, FlowSteps.clarify],
    ctx:          ctx,
    displayStep:  2,
    displayTotal: 3,
  );

  if (result[PipelineSlot.flowExit] == 'true') {
    _saveCheckpoint(result, checkpointPath);
    print(
      '\n  ${ansi.green}✓${ansi.reset}  Checkpoint saved  '
      '${ansi.dim}→${ansi.reset}  $checkpointPath\n'
      '  Resume with:  ${ansi.bold}claudart flow${ansi.reset}\n',
    );
    exit_(0);
  }

  if (result[PipelineSlot.approved] != 'true') {
    print('\n  Flow aborted — handoff not written.\n');
    exit_(0);
  }

  return result;
}

// ── Handoff write helper ──────────────────────────────────────────────────────

Future<void> _writeHandoff(
  PipelineContext       ctx,
  String                workspace,
  FileIO                fileIO,
  Never Function(int)   exit_,
) async {
  final handoffContent =
      tagOrNull(ctx[PipelineSlot.construct] ?? '', RouteTag.handoff.wireTag);
  if (handoffContent == null || handoffContent.isEmpty) {
    print(
      '\n  ${ansi.red}✗${ansi.reset}  Construct step produced no handoff.\n'
      '  Is claude CLI installed and authenticated?\n',
    );
    exit_(1);
  }

  final handoffPath = handoffPathFor(workspace);
  stdout.write('\n  ${ansi.cyan}·${ansi.reset}  Writing handoff…');
  fileIO.write(handoffPath, handoffContent.trim());
  stdout.write(
    '\x1B[2K\r  ${ansi.green}✓${ansi.reset}  Handoff written  '
    '${ansi.dim}→${ansi.reset}  $handoffPath\n\n',
  );
  print('  Next:  ${ansi.bold}claudart save${ansi.reset}  ${ansi.dim}→${ansi.reset}  then /debug in Zed\n');
}

// ── Checkpoint I/O ────────────────────────────────────────────────────────────

void _saveCheckpoint(PipelineContext ctx, String path) {
  final json = jsonEncode({
    'createdAt': DateTime.now().toIso8601String(),
    ...ctx.toCheckpointJson(),
  });
  File(path).writeAsStringSync(json);
}

