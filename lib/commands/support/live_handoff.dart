// live_handoff.dart — what to do when a handoff is live and a command is about
// to start a session over it
//
// `setup` and `flow` are two ways into a session. Both must not lose a session
// that is under way, so both ask first: continue it, start fresh, or go back.
// Starting fresh archives the live handoff before anything replaces it. This
// was measured with the real binary: `setup` asked and archived; `flow` asked
// nothing, archived nothing and the replaced handoff survived nowhere.

import '../../generated/user_text.g.dart';
import '../../io/file_io.dart';
import '../../registry.dart';
import '../../session/session_ops.dart';
import '../../session/session_state.dart';
import '../../config/paths.dart';
import '../../ui/ansi.dart' as ansi;
import '../../ui/menu.dart';
import '../../ui/render.dart' as render;

/// What the owner chooses about a live handoff.
enum LiveHandoffMenu {
  /// Keep the session and stop: nothing is written.
  resume,

  /// Archive the live handoff, then start a new session over it.
  startFresh,

  /// Cancel: nothing is written.
  back;

  String get label => switch (this) {
        resume => '${ansi.c(ansi.green, 'Continue')}  resume existing session',
        startFresh => '${ansi.c(ansi.yellow, 'Start fresh')}  '
            'overwrite handoff with new context',
        back => 'Back',
      };
}

String _truncate(String s, {int max = 60}) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

/// Settles a handoff that is live when a command is about to start a session.
///
/// Returns the status the new session starts from: [HandoffStatus.noHandoff]
/// when no handoff is live, or the live one's status once it has been
/// archived. When the owner continues or goes back the command exits through
/// [exit_] with 0 and writes nothing; [resumeText] and [cancelledText] are what
/// it says then.
HandoffStatus settleLiveHandoff({
  required FileIO io,
  required RegistryEntry entry,
  required String? gitBranch,
  required int Function(List<String> items) pick,
  required Never Function(int code) exit_,
  required UserText resumeText,
  required UserText cancelledText,
}) {
  final workspace = entry.workspacePath;
  final handoffFile = handoffPathFor(workspace);
  final existing = io.fileExists(handoffFile) ? io.read(handoffFile) : '';
  if (existing.isEmpty) return HandoffStatus.noHandoff;
  final state = SessionState.parse(existing);
  if (!state.hasActiveContent) return HandoffStatus.noHandoff;

  final statusColour = render.statusColour(state.status);
  print(UserText.projectHeadingRule.format({'name': entry.name}));
  print(UserText.killBranch.format({'branch': gitBranch ?? state.branch}));
  print(UserText.statusValueLine
      .format({'status': ansi.c(statusColour, state.status.value)}));
  print(UserText.killBug.format({'text': _truncate(state.bug.text)}));
  print('');

  switch (chooseFrom(LiveHandoffMenu.values, (m) => m.label, pick)) {
    case LiveHandoffMenu.back:
      print(cancelledText.template);
      exit_(0);
    case LiveHandoffMenu.resume:
      print(resumeText.template);
      exit_(0);
    case LiveHandoffMenu.startFresh:
      break;
  }
  final archivedName = archiveCurrentHandoff(workspace: workspace, io: io);
  if (archivedName != null) {
    print(ansi.c(
      ansi.dim,
      UserText.previousSessionArchived.format({'archivedName': archivedName}),
    ));
  }
  return state.status;
}
