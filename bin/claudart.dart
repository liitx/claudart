import 'dart:io';
import 'package:args/args.dart';
import '../lib/commands/setup.dart';
import '../lib/commands/status.dart';
import '../lib/commands/teardown.dart';

const _usage = '''
claudart — Dart CLI for structured project debug and suggestion sessions

Usage:
  claudart <command> [path]

Commands:
  setup [path]   Start a new session (path defaults to current directory)
  status         Show current session state
  teardown       Close session: update skills, archive handoff, suggest commit

Options:
  -h, --help   Show this help message
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false);

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (_) {
    print(_usage);
    exit(1);
  }

  if (parsed['help'] as bool || parsed.rest.isEmpty) {
    print(_usage);
    exit(0);
  }

  final command = parsed.rest.first;
  final path = parsed.rest.length > 1 ? parsed.rest[1] : '.';

  switch (command) {
    case 'setup':
      await runSetup(projectPath: path);
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
