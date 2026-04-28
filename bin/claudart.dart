import 'dart:io';
import 'package:claudart/git_utils.dart';
import 'package:claudart/version.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/commands/archives.dart';
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
import 'package:claudart/commands/rotate.dart';
import 'package:claudart/commands/teardown.dart';
import 'package:claudart/commands/unlink.dart';

const _usage = '''
claudart — Dart CLI for structured project debug and suggestion sessions

Usage:
  claudart                Run the interactive launcher (list projects, start workflow)
  claudart <command> [arguments]

Commands:
  archives               List session archives for the current project; resume or view snapshots
  init                   Initialize the workspace with generic starter knowledge
  init --project <name>  Add a project knowledge file to the workspace
  link [project-name]    Symlink workspace into current project (detects name from git if omitted)
  unlink                 Remove workspace symlinks from current project
  setup [path]           Start a new session (path defaults to current directory)
  status [--prompt]      Show current session state; --prompt outputs a compact colored string for shell RPROMPT/PS1
  teardown               Close session: update knowledge, archive handoff, suggest commit
  suggest                Run suggest pipeline: haiku reads scope files, sonnet writes handoff KT
  flow                   [experimental] Agent-constructed session: classify intent, plan, approve, build handoff
  save                   Checkpoint session: snapshot handoff, deposit confirmed facts to skills
  rotate                 Archive current session, run build gate, seed next handoff from Pending Issues
  kill                   Abandon session: archive handoff, remove symlink (no skills update)
  preflight <op>         Sync check before starting an operation (op: debug | save | test)
  scan [--scope lib|full|handoff] [--full]  Re-scan project for sensitive tokens
  report [--file-issue]  Show diagnostic report; --file-issue files GitHub issues
  map                    Generate token_map.md from token_map.json
  experiment <name> -- <cmd> [args]  Run a command and tee output to experiments/<name>_<ts>.ansi
  compile                Recompile the claudart binary and install it to ~/bin/claudart
  version                Print the current claudart version

Options:
  -h, --help       Show this help message
  --version        Print the current claudart version
''';

Future<void> main(List<String> args) async {
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

  switch (command) {
    case 'archives':
      await runArchives();
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
    case 'suggest':
      await runSuggest();
    case 'debug':
      await runDebug();
    case 'flow':
      await runFlow();
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
    case 'compile':
      exit(_compile());
    case 'version':
      print(claudartVersion);
    default:
      print('Unknown command: $command\n');
      print(_usage);
      exit(1);
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
