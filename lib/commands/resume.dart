// resume.dart — claudart resume: pre-populate setup from the most recent archive
//
// PLAN.md Phase 4. Loads the newest archive entry for the current project,
// reads its handoff snapshot, and calls runSetup with Bug/Expected/Files
// pre-filled as defaults — the operator can accept them (press enter) or
// override, same as any other promptWithDefault-backed question.

import '../session/handoff_placeholder.dart';
import 'package:path/path.dart' as p;
import '../io/file_io.dart';
import '../session/md_io.dart';
import '../config/paths.dart';
import '../session/teardown_utils.dart' show readSubSection;
import '../workspace/workspace_index.dart';
import 'setup.dart';
import 'support/project_resolution.dart';
import 'support/command_seams.dart';
import '../generated/user_text.g.dart';
import '../io/process_exit.dart';
import '../io/exit_reason.dart';

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
  final exit_ = exitFn ?? exitProcess;

  final project = requireProject(
    CommandSeams(
      io: fileIO,
      exitFn: exit_,
      projectRootOverride: projectRootOverride,
    ),
  );
  final entry = project.entry;
  printProjectLine(entry);

  final workspace = entry.workspacePath;
  final archives = loadIndex(workspace, io: fileIO);
  if (archives.isEmpty) {
    print(UserText.resumeNoArchivesFoundForThisProject.template);
    leaveFor(ExitReason.resumeNoArchives, exit_: exit_);
  }

  final newest = archives.first;
  final snapshotPath = p.join(archiveDirFor(workspace), newest.handoffFile);
  final snapshot = fileIO.fileExists(snapshotPath) ? fileIO.read(snapshotPath) : '';

  print(UserText.resumeResumingFrom.format({'handoffFile': newest.handoffFile, 'branch': newest.branch}));

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
