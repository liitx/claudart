import 'dart:io';
import '../lib/commands/init.dart';
import '../lib/commands/launch.dart';
import '../lib/commands/link.dart';
import '../lib/commands/map_cmd.dart';
import '../lib/commands/report.dart';
import '../lib/commands/scan.dart';
import '../lib/commands/setup.dart';
import '../lib/commands/status.dart';
import '../lib/commands/teardown.dart';
import '../lib/commands/unlink.dart';

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
  status                 Show current session state
  teardown               Close session: update knowledge, archive handoff, suggest commit
  scan [--scope lib|full|handoff] [--full]  Re-scan project for sensitive tokens
  report [--file-issue]  Show diagnostic report; --file-issue files GitHub issues
  map                    Generate token_map.md from token_map.json

Options:
  -h, --help   Show this help message
''';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
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
      await runSetup(projectPath: rest.isNotEmpty ? rest.first : '.');
    case 'status':
      runStatus();
    case 'teardown':
      await runTeardown();
    case 'scan':
      String? scope;
      bool full = rest.contains('--full');
      for (var i = 0; i < rest.length; i++) {
        if (rest[i].startsWith('--scope=')) {
          scope = rest[i].substring('--scope='.length);
        } else if (rest[i] == '--scope' && i + 1 < rest.length) {
          scope = rest[i + 1];
        }
      }
      await runScan(scope: scope, full: full);
    case 'report':
      final fileIssue = rest.contains('--file-issue');
      await runReport(fileIssue: fileIssue);
    case 'map':
      runMap();
    default:
      print('Unknown command: $command\n');
      print(_usage);
      exit(1);
  }
}
