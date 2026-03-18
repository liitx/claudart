import 'dart:io';
import 'package:claudart/git_utils.dart';
import 'package:claudart/registry.dart';
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
import 'package:claudart/commands/status.dart';
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/commands/teardown.dart';
import 'package:claudart/commands/unlink.dart';

const _usage = '''
claudart — Dart CLI for structured project debug and suggestion sessions

Usage:
  claudart                Run the interactive launcher (list projects, start workflow)
  claudart <command> [arguments]

Commands:
  init                   Initialize the workspace with generic starter knowledge
  init --project <name>  Add a project knowledge file to the workspace
  link [project-name]    Symlink workspace into current project (detects name from git if omitted)
  unlink                 Remove workspace symlinks from current project
  setup [path]           Start a new session (path defaults to current directory)
  status [--prompt]      Show current session state; --prompt outputs a compact colored string for shell RPROMPT/PS1
  teardown               Close session: update knowledge, archive handoff, suggest commit
  save                   Checkpoint session: snapshot handoff, deposit confirmed facts to skills
  rotate                 Archive current session, run build gate, seed next handoff from Pending Issues
  kill                   Abandon session: archive handoff, remove symlink (no skills update)
  preflight <op>         Sync check before starting an operation (op: debug | save | test)
  scan [--scope lib|full|handoff] [--full]  Re-scan project for sensitive tokens
  report [--file-issue]  Show diagnostic report; --file-issue files GitHub issues
  map                    Generate token_map.md from token_map.json
  experiment <name> -- <cmd> [args]  Run a command and tee output to experiments/<name>_<ts>.ansi

Options:
  -h, --help   Show this help message
''';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == '-h' || args.firstOrNull == '--help') {
    print(_usage);
    exit(0);
  }

  if (args.isEmpty) {
    await runLauncher();
    exit(0);
  }

  final command = args.first;
  final rest = args.skip(1).toList();

  switch (command) {
    case 'init':
      await runInit(rest);
    case 'link':
      await runLink(rest);
    case 'unlink':
      runUnlink();
    case 'setup':
      await runSetup(
        projectRootOverride: rest.isNotEmpty ? rest.first : null,
      );
    case 'status':
      await runStatus(prompt: rest.contains('--prompt'));
    case 'teardown':
      await runTeardown();
    case 'save':
      await runSave();
    case 'rotate':
      await runRotate();
    case 'kill':
      await runKill();
    case 'preflight':
      final op = rest.isNotEmpty ? rest.first : 'test';
      await runPreflightCmd(op);
    case 'scan':
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
      final scanWorkspace = scanRoot != null
          ? Registry.load().findByProjectRoot(scanRoot)?.workspacePath
          : null;
      await runScan(scope: scope, full: full, workspacePath: scanWorkspace);
    case 'report':
      final fileIssue = rest.contains('--file-issue');
      final reportRoot = detectGitContext()?.root;
      final reportWorkspace = reportRoot != null
          ? Registry.load().findByProjectRoot(reportRoot)?.workspacePath
          : null;
      await runReport(fileIssue: fileIssue, workspacePath: reportWorkspace);
    case 'map':
      final mapRoot = detectGitContext()?.root;
      final mapWorkspace = mapRoot != null
          ? Registry.load().findByProjectRoot(mapRoot)?.workspacePath
          : null;
      runMap(workspacePath: mapWorkspace);
    case 'experiment':
      await runExperiment(rest);
    default:
      print('Unknown command: $command\n');
      print(_usage);
      exit(1);
  }
}
