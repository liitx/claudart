
import 'dart:io';
import '../config/config.dart' show loadWorkspaceConfig;
import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';
import '../io/file_io.dart';
import '../logging/logger.dart';
import 'support/claudart_command.dart';
import '../session/md_io.dart';
import 'support/scope_files.dart';
import '../config/paths.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/flows/suggest_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import '../session/session_ops.dart';
import '../session/handoff_event.dart';
import '../session/handoff_placeholder.dart';
import '../session/invalid_handoff_transition_exception.dart';
import '../session/session_state.dart' show HandoffStatus;
import '../ui/menu.dart';
import '../workspace/workspace_config.dart';
import 'support/project_resolution.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';

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

  final workspace    = entry.workspacePath;
  final wsConfig     = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode   = wsConfig?.owner.strict ?? false;
  final exec         = executor ??
      PipelineExecutor(
        strict: strictMode,
        stepTimeout: loadWorkspaceConfig(workspace, io: fileIO).stepTimeout,
      );

  // Every pipeline event the executor publishes is logged for as long as the
  // executor lives, so a failure, a timeout or a step that never finished
  // leaves a record.
  final logger = SessionLogger.forEntry(entry, io: fileIO);
  logger.logPipelineEvents(exec.events, command: ClaudartCommand.suggest.name);
  final handoffFile  = handoffPathFor(workspace);

  if (!fileIO.fileExists(handoffFile)) {
    print(UserText.suggestNoHandoffFoundRunClaudartSetup.template);
    exit_(1);
  }

  var handoff = fileIO.read(handoffFile);
  final status  = readHandoffStatus(handoff);

  // Fail before spending any model call when the state machine would reject
  // the write this run ends with.
  if (status.after(HandoffEvent.saveConfirmedReady) == null) {
    throw InvalidHandoffTransitionException(
      status,
      HandoffEvent.saveConfirmedReady,
    );
  }

  if (status == HandoffStatus.readyForDebug ||
      status == HandoffStatus.debugInProgress) {
    print(
      '\n  ${ansi.bold}⚠${ansi.reset}  Handoff status is '
      '${ansi.bold}${status.value}${ansi.reset} — suggest already ran.',
    );
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

  // Picking up a blocked handoff (needs-suggest) moves it back to
  // investigating before any model call.
  if (status.after(HandoffEvent.suggestResumed) != null) {
    handoff = applyHandoffEvent(
      handoff,
      HandoffEvent.suggestResumed,
      onTransition: (transition) => logger.logTransition(
        command: ClaudartCommand.suggest.name,
        transition: transition,
      ),
    );
    fileIO.write(handoffFile, handoff);
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
    print(UserText.debugIsClaudeCliInstalledAndAuthenticated.template);
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
      print(UserText.suggestExitHandoffNotWritten.template);
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

  // The write below moves the status to readyForDebug, which says the
  // knowledge transfer is complete. An analysis with no root cause or no
  // files in play is not one, so nothing is written and the status stays.
  if (HandoffPlaceholder.isBlank(rootCause.trim()) ||
      HandoffPlaceholder.isBlank(scopeFiles.trim())) {
    throw ClaudartException(FailureType.knowledgeTransferNotConverged);
  }

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
  updated = applyHandoffEvent(
    updated,
    HandoffEvent.saveConfirmedReady,
    onTransition: (transition) => logger.logTransition(
      command: ClaudartCommand.suggest.name,
      transition: transition,
    ),
  );
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
