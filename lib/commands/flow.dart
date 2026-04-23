// flow.dart — claudart flow command
//
// Opens an agent-constructed session. The user provides a freeform prompt;
// the pipeline classifies intent, generates a dependency-ordered plan, awaits
// approval, then constructs the handoff automatically.
//
// Differs from suggest: the agent builds the handoff, not the user.
// Experimental variant — treat as a preview feature.

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

  // Phase 2: plan (sonnet) — includes approval gate
  ctx = await resolvedExec.runFuture(
    steps:        [FlowSteps.plan, FlowSteps.clarify],
    ctx:          ctx,
    displayStep:  2,
    displayTotal: 3,
  );

  // If approval was declined, the stream terminates at PipelineCompleted
  // without running construct — the handoff slot will be empty.
  if (ctx['construct'] == null && ctx['plan'] != null) {
    // Plan was generated but user declined — check if ctx has plan text
    final planText = tagOrNull(ctx['plan'] ?? '', 'PLAN');
    if (planText == null) {
      // Declined before plan was approved
      print('\n  Flow aborted — handoff not written.\n');
      exit_(0);
    }
  }

  // Phase 3: construct (sonnet) — runs after approval
  ctx = await resolvedExec.runFuture(
    steps:        [FlowSteps.construct],
    ctx:          ctx,
    displayStep:  3,
    displayTotal: 3,
  );

  // ── Write handoff ──────────────────────────────────────────────────────────

  final handoffContent = tagOrNull(ctx['construct'] ?? '', 'HANDOFF');
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

// ── Display ───────────────────────────────────────────────────────────────────

void _printHeader(String title) {
  final bar = '═' * (title.length + 4);
  print('\n${ansi.bold}$bar${ansi.reset}');
  print('${ansi.bold}  $title${ansi.reset}');
  print('${ansi.bold}$bar${ansi.reset}\n');
}
