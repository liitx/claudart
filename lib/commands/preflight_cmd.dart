import 'dart:io';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../config/paths.dart';
import '../session/sync_check.dart';
import 'support/project_resolution.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';
import '../io/process_exit.dart';

/// Runs a preflight sync check for [operation] and prints results.
///
/// Operations: `'debug'`, `'save'`, `'test'`.
///
/// Exits 0 when clean or warnings only (workflow can continue).
/// Exits 1 when errors are present (workflow must stop).
Future<void> runPreflightCmd(
  String operation, {
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exitProcess;

  // 1 — Git context: project root + current branch in one call.
  final project = requireProject(
    CommandSeams(
      io: fileIO,
      exitFn: exit_,
      projectRootOverride: projectRootOverride,
    ),
    withGitContext: true,
  );
  final entry = project.entry;
  final gitCtx = project.gitContext;
  final currentBranch =
      gitCtx?.branch; // null when override is used (e.g. tests)
  printProjectLine(entry);

  final workspace = entry.workspacePath;

  // 2 — Read handoff.
  final handoffFile = handoffPathFor(workspace);
  final handoffContent =
      fileIO.fileExists(handoffFile) ? fileIO.read(handoffFile) : '';

  // 3 — Read skills.
  final skillsFile = skillsPathFor(workspace);
  final skillsContent =
      fileIO.fileExists(skillsFile) ? fileIO.read(skillsFile) : '';

  // 4 — Parse operation string once at boundary.
  final op = ClaudartOperation.fromString(operation);
  if (op == null) {
    print(UserText.preflightUnknownOperation.format({
      'operation': operation,
      'operations': ClaudartOperation.values.map((o) => o.name).join(', '),
    }));
    exit_(1);
  }

  // 5 — Read test files when operation is 'test'.
  final testFileContents = <String, String>{};
  if (op == ClaudartOperation.test) {
    final commandsDir = claudeCommandsDirFor(workspace);
    if (fileIO.dirExists(commandsDir)) {
      for (final name in _testFileNames) {
        final filePath = p.join(commandsDir, name);
        if (fileIO.fileExists(filePath)) {
          testFileContents[name] = fileIO.read(filePath);
        }
      }
    }
  }

  // 6 — Run preflight.
  final result = runPreflight(
    operation: op,
    currentBranch: currentBranch,
    handoffContent: handoffContent,
    skillsContent: skillsContent,
    testFileContents: testFileContents,
  );

  // 6 — Print results.
  if (result.isClean) {
    print(UserText.preflightCmdPreflightCleanNoIssuesFound.template);
    exit_(0);
  }

  for (final issue in result.issues) {
    print(issue.toString());
  }

  // Warnings allow continuation; errors block it.
  exit_(result.hasErrors ? 1 : 0);
}

// Test command files checked for coverage gaps.
const _testFileNames = [
  'test_session.md',
  'test_registry.md',
  'test_save.md',
  'test_launch.md',
  'test_link.md',
  'test_commands.md',
];
