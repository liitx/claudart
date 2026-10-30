import 'dart:io';
import '../file_io.dart';
import '../session/pending_confirmation.dart';
import '../ui/render.dart' as render;
import 'project_resolution.dart';
import 'command_seams.dart';

/// Sets or clears the pending confirmation for the current project's
/// workspace. A skill's confirmation-gate step (see
/// pipeline/agents/confirmation.dart) runs this via the Bash tool it
/// already has access to, so the pending state survives the
/// stateless-per-call boundary any consumer dispatches through.
///
/// Usage:
///   claudart confirm-pending --question "`<text>`" --on-confirm "`<cli command>`"
///   claudart confirm-pending --clear
Future<void> runConfirmPending(
  List<String> args, {
  FileIO? io,
  String? projectRootOverride,
  Never Function(int code)? exitFn,
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

  if (args.contains('--clear')) {
    PendingConfirmationStore.clear(workspace, io: fileIO);
    print('${render.header('CONFIRM PENDING')}\n\n✓ Cleared.');
    return;
  }

  final question = _valueOf(args, '--question');
  final onConfirm = _valueOf(args, '--on-confirm');

  if (question == null || onConfirm == null) {
    print('✗ Both --question and --on-confirm are required (or pass --clear).');
    exit_(1);
  }

  PendingConfirmationStore.write(
    workspace,
    PendingConfirmation(
      question: question,
      onConfirmCommand: onConfirm,
      createdAt: DateTime.now().toUtc(),
    ),
    io: fileIO,
  );

  print('${render.header('CONFIRM PENDING')}\n\n'
      '✓ Set — will run `$onConfirm` when the user confirms.');
}

String? _valueOf(List<String> args, String flag) {
  final flagIndex = args.indexOf(flag);
  if (flagIndex == -1 || flagIndex + 1 >= args.length) return null;
  return args[flagIndex + 1];
}
