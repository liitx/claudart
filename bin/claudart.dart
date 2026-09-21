import 'dart:io';
import 'package:claudart/git_utils.dart';
import 'package:claudart/pipeline/debug_mode.dart';
import 'package:claudart/version.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/commands/add.dart';
import 'package:claudart/commands/archives.dart';
import 'package:claudart/commands/chat_shell.dart';
import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/commands/confirm_pending.dart';
import 'package:claudart/commands/doctor.dart';
import 'package:claudart/commands/experiment.dart';
import 'package:claudart/commands/init.dart';
import 'package:claudart/commands/kill.dart';
import 'package:claudart/commands/save.dart';
import 'package:claudart/commands/launch.dart';
import 'package:claudart/commands/link.dart';
import 'package:claudart/commands/map_cmd.dart';
import 'package:claudart/commands/preflight_cmd.dart';
import 'package:claudart/commands/report.dart';
import 'package:claudart/commands/scan.dart';
import 'package:claudart/commands/setup.dart';
import 'package:claudart/commands/debug.dart';
import 'package:claudart/commands/flow.dart';
import 'package:claudart/commands/suggest.dart';
import 'package:claudart/commands/status.dart';
import 'package:claudart/commands/resume.dart';
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/session/run_mode.dart';
import 'package:claudart/commands/teardown.dart';
import 'package:claudart/commands/unlink.dart';

const _usage = '''
claudart — Dart CLI for structured project debug and suggestion sessions

Usage:
  claudart                Run the interactive launcher (list projects, start workflow)
  claudart <command> [arguments]

Commands:
  chat                   Open the interactive chat shell: greeting, then dispatch to flow/suggest
  archives               List session archives for the current project; resume or view snapshots
  add                    Scaffold a brand-new project: PLAN.md, CLAUDE.md, registry entry, .claude symlink, Claude Code memory registration
  init                   Initialize the workspace with generic starter knowledge
  init --project <name>  Add a project knowledge file to the workspace
  link [project-name]    Symlink workspace into current project (detects name from git if omitted); --sensitive / --no-sensitive set sensitivity mode without asking
  unlink                 Remove workspace symlinks from current project
  setup [path]           Start a new session (path defaults to current directory)
  status [--prompt]      Show current session state; --prompt outputs a compact colored string for shell RPROMPT/PS1
  teardown [--headless]  Close session: update knowledge, archive handoff, suggest commit; --headless resolves every decision itself and prints a summary instead of prompting
  suggest                Run suggest pipeline: haiku classifies the bug and reads scope files, routed model writes handoff KT
  debug                  Run debug pipeline: haiku reads scope files, routed model emits EDIT_FILE edits written to disk
  flow                   [experimental] Agent-constructed session: classify intent, plan, approve, build handoff
  save                   Checkpoint session: snapshot handoff, deposit confirmed facts to skills
  rotate [--headless]    Archive current session, run build gate, seed next handoff from Pending Issues; --headless skips the confirmation (needed when there is no terminal to ask on)
  kill [--headless]      Abandon session: archive handoff, remove symlink (no skills update); --headless skips the confirmation but never clears a workspace lock
  resume                 Pre-populate setup from the most recent archive entry
  confirm-pending --question <q> --on-confirm <cmd>
                         Set the pending confirmation for this workspace
  confirm-pending --clear  Clear the pending confirmation
  preflight <op>         Sync check before starting an operation (op: debug | save | test)
  scan [--scope lib|full|handoff] [--full]  Re-scan project for sensitive tokens
  report [--file-issue]  Show diagnostic report; --file-issue files GitHub issues
  map                    Generate token_map.md from token_map.json
  experiment <name> -- <cmd> [args]  Run a command and tee output to experiments/<name>_<ts>.ansi
  compile                Recompile the claudart binary and install it to ~/bin/claudart
  doctor                 Fresh-machine verification: tools on PATH, git identity, gh auth, provider env
  version                Print the current claudart version

Options:
  -h, --help       Show this help message
  --version        Print the current claudart version
  --debug          Write per-step trace (system prompt, message, token
                   counts, cost) to \$CLAUDART_DEBUG_PATH (default
                   /tmp/claudart_debug.log). Same effect as setting
                   CLAUDART_DEBUG=1.
''';

Future<void> main(List<String> rawArgs) async {
  // Strip top-level option flags (`--debug`, …) before command dispatch
  // so subcommand arg parsing doesn't see them. `--debug` is repeatable
  // / position-independent — anywhere in argv enables it.
  final args = <String>[];
  for (final arg in rawArgs) {
    if (arg == '--debug') {
      setDebugEnabled(true);
      continue;
    }
    args.add(arg);
  }

  if (args.firstOrNull == '-h' || args.firstOrNull == '--help') {
    print(_usage);
    exit(0);
  }

  if (args.firstOrNull == '--version' || args.firstOrNull == 'version') {
    print(claudartVersion);
    exit(0);
  }

  if (args.isEmpty) {
    await runLauncher();
    exit(0);
  }

  final command = args.first;
  final rest = args.skip(1).toList();

  final claudartCommand = ClaudartCommand.fromString(command);
  if (claudartCommand == null) {
    print('Unknown command: $command\n');
    print(_usage);
    exit(1);
  }

  switch (claudartCommand) {
    case ClaudartCommand.chat:
      await runChatShell();
    case ClaudartCommand.archives:
      await runArchives();
    case ClaudartCommand.add:
      await runAdd();
    case ClaudartCommand.init:
      await runInit(rest);
    case ClaudartCommand.link:
      await runLink(rest);
    case ClaudartCommand.unlink:
      runUnlink();
    case ClaudartCommand.setup:
      await runSetup(
        projectRootOverride: rest.isNotEmpty ? rest.first : null,
      );
    case ClaudartCommand.status:
      await runStatus(prompt: rest.contains('--prompt'));
    case ClaudartCommand.teardown:
      await runTeardown(
        mode: rest.contains('--headless') ? RunMode.headless : RunMode.interactive,
      );
    case ClaudartCommand.suggest:
      await runSuggest();
    case ClaudartCommand.debug:
      await runDebug();
    case ClaudartCommand.flow:
      await runFlow();
    case ClaudartCommand.save:
      await runSave();
    case ClaudartCommand.rotate:
      final rotated = await runRotate(
        mode: rest.contains('--headless') ? RunMode.headless : RunMode.interactive,
      );
      // A failed build gate must be visible to scripts (zedup, CI): exit 1.
      if (rotated == RotateResult.buildFailed) exit(1);
    case ClaudartCommand.kill:
      await runKill(
        mode: rest.contains('--headless') ? RunMode.headless : RunMode.interactive,
      );
    case ClaudartCommand.resume:
      await runResume();
    case ClaudartCommand.confirmPending:
      await runConfirmPending(rest);
    case ClaudartCommand.preflight:
      final op = rest.isNotEmpty ? rest.first : 'test';
      await runPreflightCmd(op);
    case ClaudartCommand.scan:
      String? scope;
      final bool full = rest.contains('--full');
      for (var i = 0; i < rest.length; i++) {
        if (rest[i].startsWith('--scope=')) {
          scope = rest[i].substring('--scope='.length);
        } else if (rest[i] == '--scope' && i + 1 < rest.length) {
          scope = rest[i + 1];
        }
      }
      final scanRoot = detectGitContext()?.root;
      final scanEntry = scanRoot != null
          ? Registry.load().findByProjectRoot(scanRoot)
          : null;
      await runScan(
        scope: scope,
        full: full,
        projectRootOverride: scanEntry?.projectRoot,
        sensitivityModeOverride: scanEntry?.sensitivityMode,
        workspacePath: scanEntry?.workspacePath,
      );
    case ClaudartCommand.report:
      final fileIssue = rest.contains('--file-issue');
      final reportRoot = detectGitContext()?.root;
      final reportEntry = reportRoot != null
          ? Registry.load().findByProjectRoot(reportRoot)
          : null;
      if (reportEntry != null) print('Project  : ${reportEntry.name}');
      await runReport(fileIssue: fileIssue, workspacePath: reportEntry?.workspacePath);
    case ClaudartCommand.map:
      final mapRoot = detectGitContext()?.root;
      final mapEntry = mapRoot != null
          ? Registry.load().findByProjectRoot(mapRoot)
          : null;
      if (mapEntry != null) print('Project  : ${mapEntry.name}');
      runMap(workspacePath: mapEntry?.workspacePath);
    case ClaudartCommand.experiment:
      await runExperiment(rest);
    case ClaudartCommand.compile:
      exit(_compile());
    case ClaudartCommand.doctor:
      final doctorRoot = detectGitContext()?.root;
      final doctorEntry = doctorRoot != null
          ? Registry.load().findByProjectRoot(doctorRoot)
          : null;
      await runDoctor(workspacePath: doctorEntry?.workspacePath);
  }
}

int _compile() {
  final home = Platform.environment['HOME'] ?? '';
  final out  = '$home/bin/claudart';
  final src  = _resolveClaudartSource();

  if (src == null) {
    stderr.writeln(
      'Cannot locate claudart source. Run from the claudart repo root:\n'
      '  dart compile exe bin/claudart.dart -o \$HOME/bin/claudart',
    );
    return 1;
  }

  stdout.writeln('Compiling claudart → $out');
  final result = Process.runSync('dart', ['compile', 'exe', src, '-o', out]);

  stdout.write(result.stdout);
  if (result.stderr.toString().trim().isNotEmpty) {
    stderr.write(result.stderr);
  }

  if (result.exitCode != 0) {
    stderr.writeln('Compile failed (exit ${result.exitCode})');
    return result.exitCode;
  }

  stdout.writeln('Installed: $out');
  // Persist source path so `claudart compile` works from any directory.
  _saveSourcePath(File(src).parent.parent.path);
  return 0;
}

void _saveSourcePath(String repoRoot) {
  try {
    final dir = Directory('${Platform.environment['HOME']}/.config/claudart');
    dir.createSync(recursive: true);
    File('${dir.path}/source').writeAsStringSync(repoRoot);
  } on Exception catch (_) {}
}

/// Locates bin/claudart.dart by walking up from the running executable,
/// then falling back to .dart_tool/package_config.json,
/// then to ~/.config/claudart/source (written on first successful compile).
String? _resolveClaudartSource() {
  // 1. Walk up from the executable.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/bin/claudart.dart');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  // 2. Read package_config.json for the claudart package root.
  try {
    final configFile = File(
      '${Directory.current.path}/.dart_tool/package_config.json',
    );
    if (configFile.existsSync()) {
      final json = configFile.readAsStringSync();
      // Match both compact ("name":"claudart") and spaced ("name": "claudart") JSON.
      final nameMatch = RegExp(r'"name"\s*:\s*"claudart"').firstMatch(json);
      if (nameMatch != null) {
        final rootMatch = RegExp(r'"rootUri"\s*:\s*"([^"]+)"')
            .firstMatch(json.substring(nameMatch.start));
        if (rootMatch != null) {
          final rawUri   = rootMatch.group(1)!;
          // Resolve relative URIs (e.g. "../") against the config file's location.
          final rootPath = configFile.uri.resolve(rawUri).toFilePath();
          final candidate = File('${rootPath}bin/claudart.dart');
          if (candidate.existsSync()) return candidate.path;
        }
      }
    }
  } on Exception catch (_) {}

  // 3. Persisted path from last successful compile.
  try {
    final saved = File('${Platform.environment['HOME']}/.config/claudart/source')
        .readAsStringSync()
        .trim();
    if (saved.isNotEmpty) {
      final candidate = File('$saved/bin/claudart.dart');
      if (candidate.existsSync()) return candidate.path;
    }
  } on Exception catch (_) {}

  return null;
}
