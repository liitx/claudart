// flow.dart — claudart flow command
//
// Opens an agent-constructed session. The user provides a freeform prompt;
// the pipeline classifies intent, generates a dependency-ordered plan, awaits
// approval, then constructs the handoff automatically.
//
// Differs from suggest: the agent builds the handoff, not the user.
// Experimental variant — treat as a preview feature.

import 'support/claudart_command.dart';
import '../logging/logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/config.dart' show loadWorkspaceConfig;
import '../io/file_io.dart';
import '../io/git_utils.dart';
import '../logging/planner_log.dart';
import '../session/md_io.dart' show prompt;
import '../config/paths.dart';
import '../pipeline/agents/categorization.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/route_tag.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../util/enum_util.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../ui/render.dart' as render;
import '../workspace/workspace_config.dart';
import 'support/project_resolution.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';
import '../ui/styled_text.dart';
import '../io/process_exit.dart';
import '../session/handoff_store.dart';
import '../session/handoff_event.dart';
import '../session/session_state.dart';
import '../registry.dart';
import 'support/live_handoff.dart';

Future<void> runFlow({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
  PlannerLog? plannerLog,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items)? pickFn,
}) async {
  final fileIO  = io       ?? const RealFileIO();
  final exit_   = exitFn   ?? exitProcess;
  final planner = plannerLog ?? PlannerLog();
  final prompt_ = promptFn ?? prompt;
  final pick_   = pickFn   ?? arrowMenu;

  // ── Locate project ─────────────────────────────────────────────────────────

  final project = requireProject(
    CommandSeams(
      io: fileIO,
      exitFn: exit_,
      projectRootOverride: projectRootOverride,
    ),
  );
  final projectRoot = project.projectRoot;
  final entry = project.entry;
  printProjectLine(entry);

  // A session under way is not lost: ask first, and archive it before it is
  // replaced, as `setup` does.
  final startedFrom = settleLiveHandoff(
    io: fileIO,
    entry: entry,
    gitBranch: project.gitContext?.branch,
    pick: pick_,
    exit_: exit_,
    resumeText: UserText.flowContinueExisting,
    cancelledText: UserText.flowCancelled,
  );

  final workspace    = entry.workspacePath;
  final wsConfig     = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode   = wsConfig?.owner.strict ?? false;
  // verbose defaults to false (no CLI flag plumbs an opt-in/out yet) — an
  // unconditional true here would put pipeline-internal trace lines in
  // every user's stdout with no way to silence them.
  final resolvedExec = executor ??
      PipelineExecutor(
        strict: strictMode,
        stepTimeout: loadWorkspaceConfig(workspace, io: fileIO).stepTimeout,
      );

  // Every pipeline event the executor publishes is logged for as long as the
  // executor lives, so a failure, a timeout or a step that never finished
  // leaves a record.
  SessionLogger.forEntry(entry, io: fileIO).logPipelineEvents(
    resolvedExec.events,
    command: ClaudartCommand.flow.name,
  );

  // ── Check for saved checkpoint ─────────────────────────────────────────────

  final checkpointPath = '$workspace/$flowCheckpointFileName';

  if (fileIO.fileExists(checkpointPath)) {
    print(render.header('CLAUDART FLOW  ${ansi.dim}[resume]${ansi.reset}'));
    print(UserText.flowASavedCheckpointWasFoundFrom.template);

    try {
      final json    = jsonDecode(fileIO.read(checkpointPath)) as Map<String, dynamic>;
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
        print(UserText.flowCheckpointKeptAt.styled({'checkpointPath': checkpointPath}));
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
        await _writeHandoff(ctx, entry, fileIO, exit_, startedFrom);
        fileIO.delete(checkpointPath);
        return;
      }

      // refine: collect feedback, re-run phases 2+3 with saved context
      final feedback = prompt_('Refinement:', optional: true)?.trim() ?? '';
      var ctx = feedback.isNotEmpty
          ? savedCtx.appendClarification('Refinement: $feedback')
          : savedCtx;

      ctx = await _runPhase2(resolvedExec, ctx, checkpointPath, fileIO, exit_);
      ctx = await resolvedExec.runFuture(
        steps:        [FlowSteps.construct],
        ctx:          ctx,
        displayStep:  3,
        displayTotal: 3,
      );
      await _writeHandoff(ctx, entry, fileIO, exit_, startedFrom);
      fileIO.delete(checkpointPath);
      return;
    } on FormatException {
      print(UserText.flowCheckpointUnreadableStartingFresh.styled({}));
      fileIO.delete(checkpointPath);
    } on TypeError {
      print(UserText.flowCheckpointUnreadableStartingFresh.styled({}));
      fileIO.delete(checkpointPath);
    }
  }

  // ── Collect prompt ─────────────────────────────────────────────────────────

  print(render.header('CLAUDART FLOW  ${ansi.dim}[experimental]${ansi.reset}'));
  print(UserText.flowPromptInvitation.styled());
  final taskPrompt = prompt_('  →', optional: true)?.trim() ?? '';
  if (taskPrompt.isEmpty) {
    print(UserText.flowNoPromptEnteredAborted.template);
    exit_(0);
  }

  // ── Pipeline ───────────────────────────────────────────────────────────────

  var ctx = PipelineContext(
    projectRoot: projectRoot,
    bug:         taskPrompt,
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
  ctx = await _runPhase2(resolvedExec, ctx, checkpointPath, fileIO, exit_);

  // Phase 3: construct (sonnet)
  ctx = await resolvedExec.runFuture(
    steps:        [FlowSteps.construct],
    ctx:          ctx,
    displayStep:  3,
    displayTotal: 3,
  );

  await _writeHandoff(ctx, entry, fileIO, exit_, startedFrom);
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
  FileIO           fileIO,
  Never Function(int) exit_,
) async {
  final result = await exec.runFuture(
    steps:        [FlowSteps.plan, FlowSteps.clarify],
    ctx:          ctx,
    displayStep:  2,
    displayTotal: 3,
  );

  if (result[PipelineSlot.flowExit] == 'true') {
    _saveCheckpoint(result, checkpointPath, fileIO);
    print(UserText.flowCheckpointSaved.styled({'checkpointPath': checkpointPath}));
    exit_(0);
  }

  if (result[PipelineSlot.approved] != 'true') {
    print(UserText.flowFlowAbortedHandoffNotWritten.template);
    exit_(0);
  }

  return result;
}

// ── Handoff write helper ──────────────────────────────────────────────────────

Future<void> _writeHandoff(
  PipelineContext       ctx,
  RegistryEntry         entry,
  FileIO                fileIO,
  Never Function(int)   exit_,
  HandoffStatus         startedFrom,
) async {
  final workspace = entry.workspacePath;
  final handoffContent =
      tagOrNull(ctx[PipelineSlot.construct] ?? '', RouteTag.handoff.wireTag);
  if (handoffContent == null || handoffContent.isEmpty) {
    print(UserText.flowConstructProducedNoHandoff.styled());
    exit_(1);
  }

  final handoffPath  = handoffPathFor(workspace);
  final branch       = detectGitContext()?.branch ?? 'unknown';
  final date         = DateTime.now().toIso8601String().split('T').first;
  // Matches handoff_template.dart's established format (project name in the
  // title) so a flow-generated handoff isn't distinguishable-by-omission
  // from one save/setup would have written — matters when several
  // workspaces' handoffs are open side by side.
  final projectName  = p.basename(workspace);
  final header = '# Agent Handoff — $projectName\n\n'
      '> Session started: $date | Branch: $branch\n\n---\n\n';

  stdout.write('\n  ${ansi.cyan}·${ansi.reset}  Writing handoff…');
  // Another way into a session, like setup: it enters through an event of its
  // own and writes through the one writer. Over a live handoff it still writes
  // (as it always has), and the move is logged as rejected, so the overwrite is
  // on record.
  HandoffStore(
    io: fileIO,
    handoffFile: handoffPath,
    logger: SessionLogger.forEntry(entry, io: fileIO),
    command: ClaudartCommand.flow.name,
  ).replace(
    '$header${handoffContent.trim()}',
    from: startedFrom,
    event: HandoffEvent.flowConstructed,
  );
  stdout.write(
    '\x1B[2K\r  ${ansi.green}✓${ansi.reset}  Handoff written  '
    '${ansi.dim}→${ansi.reset}  $handoffPath\n\n',
  );
  print(UserText.flowNextClaudartSaveThenSuggestIn.styled({}));
}

// ── Checkpoint I/O ────────────────────────────────────────────────────────────

void _saveCheckpoint(PipelineContext ctx, String path, FileIO fileIO) {
  final json = jsonEncode({
    'createdAt': DateTime.now().toIso8601String(),
    ...ctx.toCheckpointJson(),
  });
  fileIO.write(path, json);
}

