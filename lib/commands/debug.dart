
import 'dart:io';
import '../session/handoff_placeholder.dart';
import 'package:path/path.dart' as p;
import '../config/config.dart' show loadWorkspaceConfig;
import '../io/file_io.dart';
import '../logging/logger.dart';
import 'support/claudart_command.dart';
import '../session/md_io.dart';
import 'support/scope_files.dart';
import '../config/paths.dart';
import '../pipeline/edit_files.dart';
import '../pipeline/flows/debug_steps.dart';
import '../pipeline/flows/flow_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../session/debug_disposition.dart';
import '../session/handoff_event.dart';
import '../session/invalid_handoff_transition_exception.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/render.dart' as render;
import '../ui/menu.dart';
import '../workspace/workspace_config.dart';
import 'support/command_seams.dart';
import 'support/project_resolution.dart';
import '../generated/user_text.g.dart';
import '../ui/styled_text.dart';
import '../session/handoff_store.dart';
import '../io/process_exit.dart';

/// Every way a `claudart debug` run can end before it applies a fix. Each is
/// logged as the run's outcome, so a run that stopped leaves a record of why.
enum DebugExitKind {
  /// The command ran outside a git repository, so no project could be found.
  notInGitRepository,

  /// The project is not linked, so it has no workspace.
  projectNotRegistered,

  /// The workspace has no handoff to debug from.
  noHandoff,

  /// The handoff lists no files in play, so there is nothing to read.
  emptyScope,

  /// The reader step gave no output, usually because the `claude` CLI is not
  /// installed or not signed in.
  readerProducedNothing,

  /// The implementer step gave no output.
  implementerProducedNothing,

  /// The owner reviewed the plan and chose not to write the files.
  ownerDeclinedWrite;

  /// The process exit code for this ending. Declining the write is a normal
  /// ending; every other kind is a failure.
  int get exitCode => switch (this) {
        DebugExitKind.ownerDeclinedWrite => 0,
        DebugExitKind.notInGitRepository ||
        DebugExitKind.projectNotRegistered ||
        DebugExitKind.noHandoff ||
        DebugExitKind.emptyScope ||
        DebugExitKind.readerProducedNothing ||
        DebugExitKind.implementerProducedNothing =>
          1,
      };
}

Future<void> runDebug({
  CommandSeams seams = const CommandSeams(),
  PipelineExecutor? executor,
  DartFileAnalyzer? dartFileAnalyzer,
}) async {
  final io = seams.io;
  final exitFn = seams.exitFn;
  final pickFn = seams.pickFn;
  final fileIO   = io       ?? const RealFileIO();
  final exit_    = exitFn   ?? exitProcess;
  final pick_    = pickFn   ?? arrowMenu;

  // Logs the kind as the run's outcome, then exits with the kind's code. Until
  // the project is known there is no workspace, so it is the global log.
  var exitLogger = SessionLogger.plain(io: fileIO);
  Never leave(DebugExitKind kind) {
    exitLogger.logInteraction(
      command: ClaudartCommand.debug.name,
      outcome: kind.name,
    );
    exit_(kind.exitCode);
  }

  // ── Locate project ──────────────────────────────────────────────────────────

  ProjectLookupFailure? lookupFailure;
  final project = lookupProject(
    seams,
    onFailure: (failure) => lookupFailure = failure,
  );
  if (project == null) {
    final failure = lookupFailure!;
    for (final line in failure.lines) {
      print(line);
    }
    leave(switch (failure) {
      ProjectLookupFailure.notInGitRepository =>
        DebugExitKind.notInGitRepository,
      ProjectLookupFailure.notRegistered => DebugExitKind.projectNotRegistered,
    });
  }
  final projectRoot = project.projectRoot;
  final entry = project.entry;
  printProjectLine(entry);
  final logger = SessionLogger.forEntry(entry, io: fileIO);
  exitLogger = logger;

  final workspace   = entry.workspacePath;
  final wsConfig    = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode  = wsConfig?.owner.strict ?? false;
  final exec        = executor ??
      PipelineExecutor(
        strict: strictMode,
        stepTimeout: loadWorkspaceConfig(workspace, io: fileIO).stepTimeout,
      );

  // Every pipeline event the executor publishes is logged for as long as the
  // executor lives, so a failure, a timeout or a step that never finished
  // leaves a record.
  logger.logPipelineEvents(exec.events, command: ClaudartCommand.debug.name);
  final handoffFile = handoffPathFor(workspace);

  if (!fileIO.fileExists(handoffFile)) {
    print(UserText.debugNoHandoffFoundRunClaudartSuggest.template);
    leave(DebugExitKind.noHandoff);
  }

  final handoff = fileIO.read(handoffFile);
  final status  = readHandoffStatus(handoff);

  // Fail before spending any model call when the state machine would reject
  // the write this run ends with. The old "Run debug anyway?" override could
  // only end in this rejection, so it is gone.
  if (status.after(HandoffEvent.fixApplied) == null) {
    throw InvalidHandoffTransitionException(status, HandoffEvent.fixApplied);
  }

  // ── Parse handoff ───────────────────────────────────────────────────────────

  final bug       = readSection(handoff, 'Bug');
  final expected  = readSection(handoff, 'Expected Behavior');
  final rootCause = readSection(handoff, 'Root Cause');
  final scope     = readSection(handoff, 'Scope');
  final files     = readScopeFiles(scope: scope, projectRoot: projectRoot, workspace: workspace, io: fileIO);

  if (files.isEmpty) {
    print(UserText.noScopeFilesRunSuggest.template);
    leave(DebugExitKind.emptyScope);
  }

  // ── Session state moves ─────────────────────────────────────────────────────
  //
  // Debug begins (debugStarted) before any model call; a step that fails
  // after that blocks the session (debugBlocked) and rethrows, so the failure
  // is never silent and the handoff never stays at ready-for-debug.


  final store = HandoffStore(
    io: fileIO,
    handoffFile: handoffFile,
    logger: logger,
    command: ClaudartCommand.debug.name,
  );

  void blockDebug() =>
      store.apply(fileIO.read(handoffFile), HandoffEvent.debugBlocked);

  Future<T> blockOnFailure<T>(Future<T> Function() step) async {
    try {
      return await step();
    } catch (_) {
      blockDebug();
      rethrow;
    }
  }

  // A run resuming from debugInProgress has no debugStarted move to make.
  if (status.after(HandoffEvent.debugStarted) != null) {
    store.apply(handoff, HandoffEvent.debugStarted);
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  print(render.header('CLAUDART DEBUG'));
  print(UserText.stageBar.styled());

  // ── Build context: prepend root cause + expected to bug ─────────────────────

  final fullBug = [
    if (bug.isNotEmpty) '## Bug\n$bug',
    if (!HandoffPlaceholder.isBlank(rootCause))
      '## Root Cause\n$rootCause',
    if (expected.isNotEmpty) '## Expected Behavior\n$expected',
  ].join('\n\n');

  // ── Phase 0: categorize ──────────────────────────────────────────────────────
  //
  // Debug re-classifies rather than trusting anything suggest may have
  // written earlier — Bug/Root Cause can change between the two commands
  // (a /save refinement, a manual edit), and one haiku call is cheap
  // enough that re-deriving is simpler and safer than a stale disk value.

  var ctx = PipelineContext(
    projectRoot: projectRoot,
    bug:         fullBug,
    expected:    expected,
    files:       files,
  );

  ctx = await blockOnFailure(
    () => exec.runFuture(
      steps:        [FlowSteps.categorize],
      ctx:          ctx,
      displayStep:  1,
      displayTotal: 4,
    ),
  );

  // ── Phase 1: reader ─────────────────────────────────────────────────────────

  ctx = await blockOnFailure(
    () => exec.runFuture(
      steps:        [DebugSteps.reader(files.length)],
      ctx:          ctx,
      displayStep:  2,
      displayTotal: 4,
    ),
  );

  if (ctx.readerOut.isEmpty) {
    blockDebug();
    print(UserText.debugIsClaudeCliInstalledAndAuthenticated.template);
    leave(DebugExitKind.readerProducedNothing);
  }

  // ── Phase 2: implementer ─────────────────────────────────────────────────────

  ctx = await blockOnFailure(
    () => exec.runFuture(
      steps:        [DebugSteps.implementer],
      ctx:          ctx,
      displayStep:  3,
      displayTotal: 4,
    ),
  );

  if (ctx.implementerOut.isEmpty) {
    blockDebug();
    leave(DebugExitKind.implementerProducedNothing);
  }

  // ── Review ───────────────────────────────────────────────────────────────────

  final changes  = tagOr(ctx.implementerOut, WireTag.changes.tagName);
  // Throws EditPlanException on a malformed plan, before any fix is applied;
  // the failure blocks the session.
  final editTags = await blockOnFailure(
    () async => parseEditFiles(ctx.implementerOut),
  );

  print(UserText.usageRule.styled({}));
  print(UserText.debugTotal.styled({'format': ctx.usage.format()}));

  print(render.header('DEBUG PLAN — REVIEW BEFORE WRITE'));
  _printSection('CHANGES', changes);

  print(UserText.debugFilesToWrite.styled({}));
  print(UserText.filesToWriteRule.styled({}));
  for (final f in editTags) {
    final abs    = p.join(projectRoot, f.path);
    final exists = File(abs).existsSync();
    final tag    = exists ? ansi.c(ansi.yellow, 'MOD') : ansi.c(ansi.green, 'NEW');
    print(UserText.debugFileTagLine.format({'tag': tag, 'path': f.path}));
  }
  print('');

  print('${ansi.dim}${'─' * 44}${ansi.reset}\n');

  final choice = pick_([
    'apply  ${ansi.dim}(write all files to disk)${ansi.reset}',
    'exit  ${ansi.dim}(quit without writing)${ansi.reset}',
  ]);

  if (choice == 1) {
    print(UserText.debugExitNoFilesWritten.template);
    leave(DebugExitKind.ownerDeclinedWrite);
  }

  // ── Phase 3: write files ─────────────────────────────────────────────────────

  stdout.write('\n  ${ansi.cyan}·${ansi.reset}  ${ansi.dim}[4/4]${ansi.reset}  Writing files…');

  // Write, then verify every file; a failure restores the files, blocks the
  // session and throws before fixApplied is applied.
  await blockOnFailure(() async {
    applyEditFiles(
      projectRoot:      projectRoot,
      planned:          editTags,
      write:            writeFile,
      dartFileAnalyzer: dartFileAnalyzer ?? dartAnalyzeClean,
    );
  });
  final written = editTags.length;

  store.rewrite(
    withDebugDisposition(
      store.apply(fileIO.read(handoffFile), HandoffEvent.fixApplied),
      DebugDisposition.done,
    ),
  );

  stdout.write(
    '\x1B[2K\r  ${ansi.green}✓${ansi.reset}  ${ansi.dim}[4/4]${ansi.reset}'
    '  $written file${written == 1 ? '' : 's'} written'
    '  ${ansi.dim}→${ansi.reset}  status: debug-complete\n\n',
  );
  print(UserText.debugNextClaudartSaveThenRunTests.styled({}));
}

// ── Display helpers ────────────────────────────────────────────────────────────

void _printSection(String title, String body) {
  final under = '─' * title.length;
  print(UserText.styledTitle.styled({'title': title}));
  print(UserText.styledUnderline.styled({'under': under}));
  for (final line in body.trim().split('\n')) {
    print(line.isEmpty ? '' : '    $line');
  }
  print('');
}
