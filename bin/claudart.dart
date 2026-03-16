import 'dart:io';
import '../lib/commands/init.dart';
import '../lib/commands/setup.dart';
import '../lib/commands/status.dart';
import '../lib/commands/teardown.dart';
import '../lib/commands/link.dart';
import '../lib/commands/unlink.dart';
import '../lib/commands/launch.dart';

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
    default:
      print('Unknown command: $command\n');
      print(_usage);
      exit(1);
  }
}
