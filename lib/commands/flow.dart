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
import '../paths.dart';
import '../pipeline/agents/categorization.dart';
import '../pipeline/agents/model_selection_agent.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../workspace/workspace_config.dart';

Future<void> runFlow({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
}) async {
  final fileIO = io   ?? const RealFileIO();
  final exit_  = exitFn ?? exit;

  // ── Locate project ─────────────────────────────────────────────────────────

  final projectRoot = projectRootOverride ?? await (await detectGitContext())?.root;
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
    _printHeader('CLAUDART FLOW  ${ansi.dim}[resume]${ansi.reset}');
    print('  A saved checkpoint was found from a previous session.\n');

    try {
      final json    = jsonDecode(checkpointFile.readAsStringSync()) as Map<String, dynamic>;
      final savedCtx = PipelineContext.fromCheckpointJson(json);
      final savedPlan = savedCtx['plan'] ?? '';

      if (savedPlan.isNotEmpty) {
        print(savedPlan);
        print('');
      }

      final resumeChoice = arrowMenu([
        'approve saved plan',
        'refine  ${ansi.dim}(add feedback · re-plan)${ansi.reset}',
        'exit  ${ansi.dim}(keep checkpoint · resume later)${ansi.reset}',
      ]);

      if (resumeChoice == 2) {
        print('\n  Checkpoint kept at:\n  ${ansi.dim}$checkpointPath${ansi.reset}\n');
        exit_(0);
      }

      checkpointFile.deleteSync();

      if (resumeChoice == 0) {
        // Skip phases 1+2; go straight to construct with the saved plan
        var ctx = savedCtx.withSlot(PipelineSlot.approved, 'true');
        ctx = await resolvedExec.runFuture(
          steps:        [FlowSteps.construct],
          ctx:          ctx,
          displayStep:  3,
          displayTotal: 3,
        );
        await _writeHandoff(ctx, workspace, fileIO, exit_);
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
      return;
    } on FormatException {
      print('  ${ansi.dim}Checkpoint unreadable — starting fresh.${ansi.reset}\n');
      checkpointFile.deleteSync();
    }
  }

  // ── Collect prompt ─────────────────────────────────────────────────────────

  _printHeader('CLAUDART FLOW  ${ansi.dim}[experimental]${ansi.reset}');
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

  // ── Pre-classify for display ───────────────────────────────────────────────

  print('');
  final classification = ModelSelectionAgent.classify(prompt);
  final preferred      = routeModel(
    classification.category,
    classification.intent,
    classification.complexity,
  );
  print(
    '  ${ansi.dim}Classified:${ansi.reset}  '
    '${classification.category.name} × '
    '${classification.intent.name} × '
    '${classification.complexity.name}'
    '  ${ansi.dim}→${ansi.reset}  ${preferred.shortName}\n',
  );

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
  final handoffContent = tagOrNull(ctx[PipelineSlot.construct] ?? '', 'HANDOFF');
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

// ── Display ───────────────────────────────────────────────────────────────────

void _printHeader(String title) {
  final bar = '═' * (title.length + 4);
  print('\n${ansi.bold}$bar${ansi.reset}');
  print('${ansi.bold}  $title${ansi.reset}');
  print('${ansi.bold}$bar${ansi.reset}\n');
}
