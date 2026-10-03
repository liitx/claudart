import 'dart:io';
import '../config.dart' show loadWorkspaceConfig;
import '../file_io.dart';
import '../git_utils.dart';
import '../md_io.dart';
import 'scope_files.dart';
import '../paths.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/flows/suggest_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import '../session/session_ops.dart';
import '../ui/menu.dart';
import '../workspace/workspace_config.dart';

Future<void> runSuggest({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items)? pickFn,
}) async {
  final fileIO   = io       ?? const RealFileIO();
  final exit_    = exitFn   ?? exit;
  final confirm_ = confirmFn ?? confirm;
  final prompt_  = promptFn ?? prompt;
  final pick_    = pickFn   ?? arrowMenu;

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
  print('Project  : ${entry.name}');

  final workspace    = entry.workspacePath;
  final wsConfig     = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode   = wsConfig?.owner.strict ?? false;
  final exec         = executor ??
      PipelineExecutor(
        strict: strictMode,
        stepTimeout: loadWorkspaceConfig(workspace, io: fileIO).stepTimeout,
      );
  final handoffFile  = handoffPathFor(workspace);

  if (!fileIO.fileExists(handoffFile)) {
    print('✗ No handoff found. Run `claudart setup` first.');
    exit_(1);
  }

  final handoff = fileIO.read(handoffFile);
  final status  = readStatus(handoff);

  if (status == 'ready-for-debug' || status == 'debug-in-progress') {
    print('\n  ${ansi.bold}⚠${ansi.reset}  Handoff status is ${ansi.bold}$status${ansi.reset} — suggest already ran.');
    if (!confirm_('Re-run suggest and overwrite?')) {
      print('Aborted.');
      exit_(0);
    }
    // Overwriting a completed handoff — preserve it first.
    archiveCurrentHandoff(workspace: workspace, io: fileIO);
  }

  // ── Parse handoff ──────────────────────────────────────────────────────────

  final bug      = readSection(handoff, 'Bug');
  final expected = readSection(handoff, 'Expected Behavior');
  final scope    = readSection(handoff, 'Scope');
  final files    = readScopeFiles(scope: scope, projectRoot: projectRoot, workspace: workspace, io: fileIO);

  if (files.isEmpty) {
    print(
      '\n✗ No files listed in ## Scope / Files in play.\n'
      '  Add file paths to the handoff via `claudart setup`, then re-run.\n',
    );
    exit_(1);
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  print(render.header('CLAUDART SUGGEST'));
  print(
    '  ${ansi.dim}[1] Classify${ansi.reset}'
    '  ${ansi.dim}›${ansi.reset}'
    '  ${ansi.dim}[2] Read files${ansi.reset}'
    '  ${ansi.dim}›${ansi.reset}'
    '  ${ansi.dim}[3] Reason${ansi.reset}'
    '  ${ansi.dim}›${ansi.reset}'
    '  ${ansi.dim}[4] Write handoff${ansi.reset}\n',
  );

  // ── Phase 0: categorize ──────────────────────────────────────────────────────
  //
  // Classifies the bug once per session (haiku) so the reasoner step below
  // can route to the right model instead of always paying full sonnet cost
  // on atomic/lookup-shaped work. debug.dart runs its own categorize step
  // rather than reading a persisted classification back — the disk
  // round-trip isn't worth the staleness risk (Bug/Root Cause can change
  // between suggest and debug) for the cost of one cheap haiku call.

  var ctx = PipelineContext(
    projectRoot: projectRoot,
    bug:         bug,
    expected:    expected,
    files:       files,
  );

  ctx = await exec.runFuture(
    steps:        [FlowSteps.categorize],
    ctx:          ctx,
    displayStep:  1,
    displayTotal: 4,
  );

  // ── Phase 1: reader ────────────────────────────────────────────────────────

  ctx = await exec.runFuture(
    steps:        [SuggestSteps.reader(files.length)],
    ctx:          ctx,
    displayStep:  2,
    displayTotal: 4,
  );

  if (ctx.readerOut.isEmpty) {
    print('     Is claude CLI installed and authenticated?');
    exit_(1);
  }

  // ── Phase 2: reasoner ──────────────────────────────────────────────────────

  ctx = await exec.runFuture(
    steps:        [SuggestSteps.reasoner],
    ctx:          ctx,
    displayStep:  3,
    displayTotal: 4,
  );

  if (ctx.reasonerOut.isEmpty) {
    exit_(1);
  }

  // ── Review + refinement loop ───────────────────────────────────────────────

  var refinePass = 1;

  while (true) {
    // Always use the most recent analysis: applier output if it exists, else reasoner.
    final analysisOut = ctx.applierOut.isNotEmpty ? ctx.applierOut : ctx.reasonerOut;

    print('\n  ${ansi.dim}──────────────────────────────────────${ansi.reset}');
    print('  ${ansi.dim}  Total  ${ctx.usage.format()}${ansi.reset}\n');

    print(render.header('SUGGEST FINDINGS — REVIEW BEFORE SAVE'));
    _printSection('ROOT CAUSE',     tagOr(analysisOut, 'ROOT_CAUSE'));
    _printSection('SCOPE FILES',    tagOr(analysisOut, 'SCOPE_FILES'));
    _printSection('MUST NOT TOUCH', tagOr(analysisOut, 'MUST_NOT_TOUCH'));
    _printSection('CONSTRAINTS',    tagOr(analysisOut, 'CONSTRAINTS'));
    print('${ansi.dim}${'─' * 44}${ansi.reset}\n');

    final choice = pick_([
      'approve  ${ansi.dim}(save analysis to handoff)${ansi.reset}',
      'refine  ${ansi.dim}(add feedback · re-analyze)${ansi.reset}',
      'exit  ${ansi.dim}(quit without saving)${ansi.reset}',
    ]);

    if (choice == 0) break;

    if (choice == 2) {
      print('\n  Exit — handoff not written.\n');
      exit_(0);
    }

    // ── Refine ────────────────────────────────────────────────────────────────

    final feedback = prompt_('What needs to change?', optional: true)?.trim() ?? '';
    if (feedback.isEmpty) continue;

    print('');
    refinePass++;

    // Rebuild ctx with fresh ephemeral state (clears __question__, __clarification__)
    // but preserves step outputs and accumulated usage.
    ctx = PipelineContext(
      projectRoot: projectRoot,
      bug:         bug,
      expected:    expected,
      files:       files,
      usage:       ctx.usage,
      slots: {
        'reader':        ctx.readerOut,
        'reasoner':      ctx.reasonerOut,
        if (ctx.applierOut.isNotEmpty) 'applier': ctx.applierOut,
        'user_feedback': feedback,
      },
    );

    ctx = await exec.runFuture(
      steps:        SuggestSteps.refinement(refinePass),
      ctx:          ctx,
      displayStep:  2,
      displayTotal: 3,
    );
  }

  // ── Phase 3: write to handoff ──────────────────────────────────────────────

  stdout.write('\n  ${ansi.cyan}·${ansi.reset}  ${ansi.dim}[4/4]${ansi.reset}  Writing handoff…');

  final analysisOut  = ctx.applierOut.isNotEmpty ? ctx.applierOut : ctx.reasonerOut;
  final rootCause    = tagOr(analysisOut, 'ROOT_CAUSE');
  final scopeFiles   = tagOr(analysisOut, 'SCOPE_FILES');
  final scopeEntries = tagOr(analysisOut, 'SCOPE_ENTRIES');
  final scopeClasses = tagOr(analysisOut, 'SCOPE_CLASSES');
  final mustNotTouch = tagOr(analysisOut, 'MUST_NOT_TOUCH');
  final constraints  = tagOr(analysisOut, 'CONSTRAINTS');

  final newScope = '''### Files in play
$scopeFiles

### Key entry points in play
$scopeEntries

### Classes / methods in play
$scopeClasses

### Must not touch
$mustNotTouch''';

  var updated = handoff;
  updated = updateSection(updated, 'Root Cause',  rootCause.trim());
  updated = updateSection(updated, 'Scope',        newScope.trim());
  updated = updateSection(updated, 'Constraints',  constraints.trim());
  updated = updateStatus(updated, 'ready-for-debug');
  updated = updated.replaceFirst(
    RegExp(r'> Updated: [^\n]+'),
    '> Updated: ${DateTime.now().toIso8601String().split('.').first}',
  );

  fileIO.write(handoffFile, updated);

  stdout.write('\x1B[2K\r  ${ansi.green}✓${ansi.reset}  ${ansi.dim}[4/4]${ansi.reset}  Handoff written  ${ansi.dim}→${ansi.reset}  status: ready-for-debug\n\n');
  print('  Next:  ${ansi.bold}claudart save${ansi.reset}  ${ansi.dim}→${ansi.reset}  then /debug in Zed\n');
}

// ── Display helpers ───────────────────────────────────────────────────────────

void _printSection(String title, String body) {
  final under = '─' * title.length;
  print('  ${ansi.bold}$title${ansi.reset}');
  print('  ${ansi.dim}$under${ansi.reset}');
  for (final line in body.trim().split('\n')) {
    print(line.isEmpty ? '' : '    $line');
  }
  print('');
}

