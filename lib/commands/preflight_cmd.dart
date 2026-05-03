import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../git_utils.dart';
import '../paths.dart';
import '../registry.dart';
import '../session/sync_check.dart';

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
  final exit_ = exitFn ?? exit;

  // 1 — Git context: project root + current branch in one call.
  final gitCtx = projectRootOverride != null ? null : await detectGitContext();
  final projectRoot = projectRootOverride ?? gitCtx?.root;
  final currentBranch =
      gitCtx?.branch; // null when override is used (e.g. tests)
  if (projectRoot == null) {
    print('✗ Not inside a git repository. Cannot detect project.');
    exit_(1);
  }

  final registry = Registry.load(io: fileIO);
  final entry = registry.findByProjectRoot(projectRoot);
  if (entry == null) {
    print('✗ No claudart session found for this project.');
    print('  Run `claudart setup` to start one.');
    exit_(1);
  }

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
    print('✓ Preflight clean — no issues found.');
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
