
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

const _cliOnly = {CommandEntry.cliSubcommand};
const _cliAndLauncher = {
  CommandEntry.cliSubcommand,
  CommandEntry.launcherMenu,
};
const _cliAndChat = {CommandEntry.cliSubcommand, CommandEntry.chatShell};
const _noEvents = <HandoffEvent>{};

/// The set of top-level `claudart <command>` subcommands. Each variant states
/// every fact about itself, so a new command cannot be added without
/// deciding them all.
enum ClaudartCommand {
  chat(
    wireName: 'chat',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  archives(
    wireName: 'archives',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  add(
    wireName: 'add',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  init(
    wireName: 'init',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: true,
    supportsProjectSelector: false,
  ),
  link(
    wireName: 'link',
    reachedFrom: _cliAndLauncher,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  unlink(
    wireName: 'unlink',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  setup(
    wireName: 'setup',
    reachedFrom: _cliAndLauncher,
    supportsHeadless: false,
    handoffEvents: {HandoffEvent.setup},
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  status(
    wireName: 'status',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  teardown(
    wireName: 'teardown',
    reachedFrom: _cliOnly,
    supportsHeadless: true,
    handoffEvents: {
      HandoffEvent.tornDown,
      HandoffEvent.reminderSaved,
    },
    recordsStepModels: true,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  suggest(
    wireName: 'suggest',
    reachedFrom: _cliAndChat,
    supportsHeadless: false,
    handoffEvents: {
      HandoffEvent.saveConfirmedReady,
      HandoffEvent.suggestResumed,
    },
    recordsStepModels: true,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  debug(
    wireName: 'debug',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: {
      HandoffEvent.debugStarted,
      HandoffEvent.debugBlocked,
      HandoffEvent.fixApplied,
    },
    recordsStepModels: true,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  flow(
    wireName: 'flow',
    reachedFrom: _cliAndChat,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: true,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  save(
    wireName: 'save',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: {
      HandoffEvent.saveUnconfirmed,
      HandoffEvent.saveConfirmedExploring,
    },
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  rotate(
    wireName: 'rotate',
    reachedFrom: _cliOnly,
    supportsHeadless: true,
    handoffEvents: {
      HandoffEvent.rotated,
      HandoffEvent.rotatedEmpty,
    },
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  kill(
    wireName: 'kill',
    reachedFrom: _cliAndLauncher,
    supportsHeadless: true,
    handoffEvents: {HandoffEvent.killed},
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  resume(
    wireName: 'resume',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  confirmPending(
    wireName: 'confirm-pending',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  preflight(
    wireName: 'preflight',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  scan(
    wireName: 'scan',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  report(
    wireName: 'report',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  map(
    wireName: 'map',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  experiment(
    wireName: 'experiment',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  compile(
    wireName: 'compile',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  doctor(
    wireName: 'doctor',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  ),
  workspaces(
    wireName: 'workspaces',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: true,
  ),
  hook(
    wireName: 'hook',
    reachedFrom: _cliOnly,
    supportsHeadless: false,
    handoffEvents: _noEvents,
    recordsStepModels: false,
    ownsProjectOption: false,
    supportsProjectSelector: false,
  );

  const ClaudartCommand({
    required this.wireName,
    required this.reachedFrom,
    required this.supportsHeadless,
    required this.handoffEvents,
    required this.recordsStepModels,
    required this.ownsProjectOption,
    required this.supportsProjectSelector,
  });

  /// Wire-format name as typed on the command line.
  final String wireName;

  /// The entry points that start this command. Every command is a subcommand;
  /// the launcher menu and the chat shell reach only a few. Checked against
  /// launch.dart and chat_shell.dart by claudart_command_test.dart.
  final Set<CommandEntry> reachedFrom;

  /// Whether the command takes `--headless` (a RunMode): it decides every
  /// prompt itself and prints a summary. Checked against each command's source.
  final bool supportsHeadless;

  /// The handoff events this command passes (through applyHandoffEvent or
  /// SessionLogger.logHandoffMove). Checked against the code by
  /// claudart_command_test.dart, which scans lib/ for each event.
  final Set<HandoffEvent> handoffEvents;

  /// Whether the command runs model steps and records, per step, which model
  /// ran (`logs/models.jsonl`). Checked against each command's source (it must
  /// log its executor's events through logPipelineEvents) by
  /// claudart_command_test.dart.
  final bool recordsStepModels;

  /// `init --project <name>` names a NEW project knowledge file; the global
  /// selector (which names an already-linked workspace) must leave it alone.
  final bool ownsProjectOption;

  /// Whether `--project <name>` can choose which registered project the command
  /// acts on: the commands that work on an existing project's session or
  /// workspace. Checked against each command's source (it must take a project
  /// override) by claudart_command_test.dart.
  final bool supportsProjectSelector;

  /// Resolves a [ClaudartCommand] from the first CLI argument. Returns null
  /// for anything unrecognized (including `version`/`--version`, handled
  /// separately before dispatch) — the caller reports "unknown command".
  static ClaudartCommand? fromString(String s) {
    for (final command in values) {
      if (command.wireName == s) return command;
    }
    return null;
  }
}
