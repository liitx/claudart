// claudart_command.dart — typed enum of every top-level CLI subcommand
//
// Single source of truth for bin/claudart.dart's dispatch. `version` is
// deliberately not a variant here — it's fully handled (and exits) before
// dispatch ever runs, so a variant for it would be permanently unreachable.
//
// Adding a new subcommand forces a new arm in every exhaustive switch over
// this enum at compile time (missing_enum_constant_in_switch: error).

import '../session/handoff_event.dart';

/// Where a command can be started from on claudart's own command-line side.
/// (zedup's TUI is a separate surface: it runs the pipelines itself and shells
/// out for `status` and `setup`; `make consumer-check` covers what it reads.)
enum CommandEntry {
  /// `claudart <command>` typed at a shell, or run by an agent's slash command.
  cliSubcommand,

  /// A menu item in the interactive launcher (`claudart` with no arguments).
  launcherMenu,

  /// A command the chat shell dispatches.
  chatShell,
}

/// The set of top-level `claudart <command>` subcommands.
enum ClaudartCommand {
  chat,
  archives,
  add,
  init,
  link,
  unlink,
  setup,
  status,
  teardown,
  suggest,
  debug,
  flow,
  save,
  rotate,
  kill,
  resume,
  confirmPending,
  preflight,
  scan,
  report,
  map,
  experiment,
  compile,
  doctor,
  workspaces;

  /// The entry points that start this command. Every command is a subcommand;
  /// the launcher menu and the chat shell reach only a few. Checked against
  /// launch.dart and chat_shell.dart by claudart_command_test.dart.
  Set<CommandEntry> get reachedFrom => switch (this) {
        setup || kill || link => {
            CommandEntry.cliSubcommand,
            CommandEntry.launcherMenu,
          },
        flow || suggest => {CommandEntry.cliSubcommand, CommandEntry.chatShell},
        chat ||
        archives ||
        add ||
        init ||
        unlink ||
        status ||
        teardown ||
        debug ||
        save ||
        rotate ||
        resume ||
        confirmPending ||
        preflight ||
        scan ||
        report ||
        map ||
        experiment ||
        compile ||
        doctor ||
        workspaces =>
          {CommandEntry.cliSubcommand},
      };

  /// Whether the command takes `--headless` (a RunMode): it decides every
  /// prompt itself and prints a summary. Checked against each command's source.
  bool get supportsHeadless => switch (this) {
        teardown || rotate || kill => true,
        chat ||
        archives ||
        add ||
        init ||
        link ||
        unlink ||
        setup ||
        status ||
        suggest ||
        debug ||
        flow ||
        save ||
        resume ||
        confirmPending ||
        preflight ||
        scan ||
        report ||
        map ||
        experiment ||
        compile ||
        doctor ||
        workspaces =>
          false,
      };

  /// The handoff events this command passes (through applyHandoffEvent or
  /// SessionLogger.logHandoffMove). Checked against the code by
  /// claudart_command_test.dart, which scans lib/ for each event.
  Set<HandoffEvent> get handoffEvents => switch (this) {
        setup => {HandoffEvent.setup},
        suggest => {HandoffEvent.saveConfirmedReady},
        debug => {HandoffEvent.fixApplied},
        rotate => {HandoffEvent.rotated, HandoffEvent.rotatedEmpty},
        teardown => {HandoffEvent.tornDown, HandoffEvent.reminderSaved},
        kill => {HandoffEvent.killed},
        chat ||
        archives ||
        add ||
        init ||
        link ||
        unlink ||
        status ||
        flow ||
        save ||
        resume ||
        confirmPending ||
        preflight ||
        scan ||
        report ||
        map ||
        experiment ||
        compile ||
        doctor ||
        workspaces =>
          const {},
      };

  /// Whether `--project <name>` can choose which registered project the command
  /// acts on: the commands that work on an existing project's session or
  /// workspace. Checked against each command's source (it must take a project
  /// override) by claudart_command_test.dart.
  bool get supportsProjectSelector => switch (this) {
        setup ||
        status ||
        suggest ||
        debug ||
        flow ||
        save ||
        rotate ||
        teardown ||
        kill ||
        resume ||
        archives ||
        preflight ||
        workspaces =>
          true,
        chat ||
        add ||
        init ||
        link ||
        unlink ||
        confirmPending ||
        scan ||
        report ||
        map ||
        experiment ||
        compile ||
        doctor =>
          false,
      };

  /// Wire-format name as typed on the command line.
  String get wireName => switch (this) {
        chat           => 'chat',
        archives       => 'archives',
        add            => 'add',
        init           => 'init',
        link           => 'link',
        unlink         => 'unlink',
        setup          => 'setup',
        status         => 'status',
        teardown       => 'teardown',
        suggest        => 'suggest',
        debug          => 'debug',
        flow           => 'flow',
        save           => 'save',
        rotate         => 'rotate',
        kill           => 'kill',
        resume         => 'resume',
        confirmPending => 'confirm-pending',
        preflight      => 'preflight',
        scan           => 'scan',
        report         => 'report',
        map            => 'map',
        experiment     => 'experiment',
        compile        => 'compile',
        doctor         => 'doctor',
        workspaces     => 'workspaces',
      };

  /// Resolves a [ClaudartCommand] from the first CLI argument. Returns null
  /// for anything unrecognized (including `version`/`--version`, handled
  /// separately before dispatch) — the caller reports "unknown command".
  static ClaudartCommand? fromString(String s) => switch (s) {
        'chat'           => chat,
        'archives'       => archives,
        'add'            => add,
        'init'           => init,
        'link'           => link,
        'unlink'         => unlink,
        'setup'          => setup,
        'status'         => status,
        'teardown'       => teardown,
        'suggest'        => suggest,
        'debug'          => debug,
        'flow'           => flow,
        'save'           => save,
        'rotate'         => rotate,
        'kill'           => kill,
        'resume'         => resume,
        'confirm-pending' => confirmPending,
        'preflight'      => preflight,
        'scan'           => scan,
        'report'         => report,
        'map'            => map,
        'experiment'     => experiment,
        'compile'        => compile,
        'doctor'         => doctor,
        'workspaces'     => workspaces,
        _                => null,
      };
}
