// resume.dart — claudart resume: pre-populate setup from the most recent archive
//
// PLAN.md Phase 4. Loads the newest archive entry for the current project,
// reads its handoff snapshot, and calls runSetup with Bug/Expected/Files
// pre-filled as defaults — the operator can accept them (press enter) or
// override, same as any other promptWithDefault-backed question.

import 'dart:io';
import '../session/handoff_placeholder.dart';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../md_io.dart';
import '../paths.dart';
import '../session/teardown_utils.dart' show readSubSection;
import '../workspace/workspace_index.dart';
import 'setup.dart';
import 'project_resolution.dart';
import 'command_seams.dart';

Future<void> runResume({
  FileIO? io,
  String? projectRootOverride,
  bool Function(String question)? confirmFn,
  String? Function(String question, {bool optional})? promptFn,
  int Function(List<String> items)? pickFn,
  Never Function(int code)? exitFn,
  FileFinderFn? fileFinderFn,
}) async {
  final fileIO = io ?? const RealFileIO();
  final exit_ = exitFn ?? exit;

  final project = requireProject(
    CommandSeams(
      io: fileIO,
      exitFn: exit_,
      projectRootOverride: projectRootOverride,
    ),
  );
  final entry = project.entry;
  print('Project  : ${entry.name}');

  final workspace = entry.workspacePath;
  final archives = loadIndex(workspace, io: fileIO);
  if (archives.isEmpty) {
    print('\nNo archives found for this project. Run `claudart setup` instead.\n');
    exit_(0);
  }

  final newest = archives.first;
  final snapshotPath = p.join(archiveDirFor(workspace), newest.handoffFile);
  final snapshot = fileIO.fileExists(snapshotPath) ? fileIO.read(snapshotPath) : '';

  print('Resuming from: ${newest.handoffFile} (${newest.branch})\n');

  await runSetup(
    io: fileIO,
    // Pass the *original* nullable override through, not the resolved
    // projectRoot — runSetup treats any non-null override as "skip live
    // git detection" (the test-bypass convention every command uses).
    // Forcing that off in live usage (no override given to runResume
    // itself) would silently disable branch detection for a perfectly
    // real, git-detectable project.
    projectRootOverride: projectRootOverride,
    confirmFn: confirmFn,
    promptFn: promptFn,
    pickFn: pickFn,
    exitFn: exitFn,
    fileFinderFn: fileFinderFn,
    defaultBug: _cleanOrNull(readSection(snapshot, 'Bug')),
    defaultExpected: _cleanOrNull(readSection(snapshot, 'Expected Behavior')),
    defaultFiles: _cleanOrNull(readSubSection(readSection(snapshot, 'Scope'), 'Files in play')),
    defaultEntryPoints: _cleanOrNull(
        readSubSection(readSection(snapshot, 'Scope'), 'Key entry points in play')),
  );
}

/// `readSection`/`readSubSection` return a placeholder string
/// (`_Not yet determined._`, `_Nothing yet._`) when the section is empty —
/// never useful as a pre-filled default.
String? _cleanOrNull(String raw) =>
    HandoffPlaceholder.isBlank(raw) ? null : raw;
