import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../md_io.dart';
import '../paths.dart';
import '../pipeline/flows/debug_steps.dart';
import '../pipeline/pipeline_context.dart';
import '../pipeline/pipeline_executor.dart';
import '../pipeline/xml_tags.dart';
import '../registry.dart';
import '../ui/ansi.dart' as ansi;
import '../ui/menu.dart';
import '../workspace/workspace_config.dart';

Future<void> runDebug({
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
  PipelineExecutor? executor,
}) async {
  final fileIO = io    ?? const RealFileIO();
  final exit_  = exitFn ?? exit;

  // ── Locate project ──────────────────────────────────────────────────────────

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

  final workspace   = entry.workspacePath;
  final wsConfig    = WorkspaceConfig.load(workspace, io: fileIO);
  final strictMode  = wsConfig?.owner.strict ?? false;
  final exec        = executor ?? PipelineExecutor(strict: strictMode);
  final handoffFile = handoffPathFor(workspace);

  if (!fileIO.fileExists(handoffFile)) {
    print('✗ No handoff found. Run `claudart suggest` first.');
    exit_(1);
  }

  final handoff = fileIO.read(handoffFile);
  final status  = readStatus(handoff);

  if (status != 'ready-for-debug') {
    stdout.write(
      '\n  ${ansi.bold}⚠${ansi.reset}  Handoff status is ${ansi.bold}$status${ansi.reset} — expected ready-for-debug.\n'
      '     Run debug anyway? [y/n] ',
    );
    final input = stdin.readLineSync();
    if (input?.toLowerCase() != 'y') {
      print('Aborted.');
      exit_(0);
    }
  }

  // ── Parse handoff ───────────────────────────────────────────────────────────

  final bug       = readSection(handoff, 'Bug');
  final expected  = readSection(handoff, 'Expected Behavior');
  final rootCause = readSection(handoff, 'Root Cause');
  final scope     = readSection(handoff, 'Scope');
  final files     = parseScopeFiles(scope, projectRoot);

  if (files.isEmpty) {
    print(
      '\n✗ No files listed in ## Scope / Files in play.\n'
      '  Run `claudart suggest` first to populate the scope.\n',
    );
    exit_(1);
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  _printHeader('CLAUDART DEBUG');
  print(
    '  ${ansi.dim}[1] Read files${ansi.reset}'
    '  ${ansi.dim}›${ansi.reset}'
    '  ${ansi.dim}[2] Implement${ansi.reset}'
    '  ${ansi.dim}›${ansi.reset}'
    '  ${ansi.dim}[3] Write files${ansi.reset}\n',
  );

  // ── Build context: prepend root cause + expected to bug ─────────────────────

  final fullBug = [
    if (bug.isNotEmpty) '## Bug\n$bug',
    if (rootCause.isNotEmpty && rootCause != '_Not yet determined._')
      '## Root Cause\n$rootCause',
    if (expected.isNotEmpty) '## Expected Behavior\n$expected',
  ].join('\n\n');

  // ── Phase 1: reader ─────────────────────────────────────────────────────────

  var ctx = PipelineContext(
    projectRoot: projectRoot,
    bug:         fullBug,
    expected:    expected,
    files:       files,
  );

  ctx = await exec.runFuture(
    steps:        [DebugSteps.reader(files.length)],
    ctx:          ctx,
    displayStep:  1,
    displayTotal: 3,
  );

  if (ctx.readerOut.isEmpty) {
    print('     Is claude CLI installed and authenticated?');
    exit_(1);
  }

  // ── Phase 2: implementer ─────────────────────────────────────────────────────

  ctx = await exec.runFuture(
    steps:        [DebugSteps.implementer],
    ctx:          ctx,
    displayStep:  2,
    displayTotal: 3,
  );

  if (ctx.implementerOut.isEmpty) {
    exit_(1);
  }

  // ── Review ───────────────────────────────────────────────────────────────────

  final changes  = tagOr(ctx.implementerOut, 'CHANGES');
  final editTags = _parseEditFiles(ctx.implementerOut);

  print('\n  ${ansi.dim}──────────────────────────────────────${ansi.reset}');
  print('  ${ansi.dim}  Total  ${ctx.usage.format()}${ansi.reset}\n');

  _printHeader('DEBUG PLAN — REVIEW BEFORE WRITE');
  _printSection('CHANGES', changes);

  print('  ${ansi.bold}FILES TO WRITE${ansi.reset}');
  print('  ${ansi.dim}─────────────${ansi.reset}');
  for (final f in editTags) {
    final abs    = p.join(projectRoot, f.path);
    final exists = File(abs).existsSync();
    final tag    = exists ? ansi.c(ansi.yellow, 'MOD') : ansi.c(ansi.green, 'NEW');
    print('    [$tag]  ${f.path}');
  }
  print('');

  print('${ansi.dim}${'─' * 44}${ansi.reset}\n');

  final choice = arrowMenu([
    'apply  ${ansi.dim}(write all files to disk)${ansi.reset}',
    'exit  ${ansi.dim}(quit without writing)${ansi.reset}',
  ]);

  if (choice == 1) {
    print('\n  Exit — no files written.\n');
    exit_(0);
  }

  // ── Phase 3: write files ─────────────────────────────────────────────────────

  stdout.write('\n  ${ansi.cyan}·${ansi.reset}  ${ansi.dim}[3/3]${ansi.reset}  Writing files…');

  var written = 0;
  for (final f in editTags) {
    final abs = p.join(projectRoot, f.path);
    writeFile(abs, f.content);
    written++;
  }

  var updated = handoff;
  updated = updateStatus(updated, 'debug-complete');
  fileIO.write(handoffFile, updated);

  stdout.write(
    '\x1B[2K\r  ${ansi.green}✓${ansi.reset}  ${ansi.dim}[3/3]${ansi.reset}'
    '  $written file${written == 1 ? '' : 's'} written'
    '  ${ansi.dim}→${ansi.reset}  status: debug-complete\n\n',
  );
  print('  Next:  ${ansi.bold}claudart save${ansi.reset}  ${ansi.dim}→${ansi.reset}  then run tests\n');
}

// ── Edit file parsing ──────────────────────────────────────────────────────────

typedef _EditFile = ({String path, String content});

List<_EditFile> _parseEditFiles(String text) {
  final result  = <_EditFile>[];
  final pattern = RegExp(
    r'<EDIT_FILE\s+path="([^"]+)">([\s\S]*?)</EDIT_FILE>',
    caseSensitive: false,
  );
  for (final m in pattern.allMatches(text)) {
    result.add((path: m.group(1)!.trim(), content: m.group(2)!.trimRight()));
  }
  return result;
}

// ── Display helpers ────────────────────────────────────────────────────────────

void _printHeader(String title) {
  final bar = '═' * (title.length + 4);
  print('\n${ansi.bold}$bar${ansi.reset}');
  print('${ansi.bold}  $title${ansi.reset}');
  print('${ansi.bold}$bar${ansi.reset}\n');
}

void _printSection(String title, String body) {
  final under = '─' * title.length;
  print('  ${ansi.bold}$title${ansi.reset}');
  print('  ${ansi.dim}$under${ansi.reset}');
  for (final line in body.trim().split('\n')) {
    print(line.isEmpty ? '' : '    $line');
  }
  print('');
}
