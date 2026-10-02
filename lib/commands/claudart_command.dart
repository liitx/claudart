// claudart_command.dart — typed enum of every top-level CLI subcommand
//
// Single source of truth for bin/claudart.dart's dispatch. `version` is
// deliberately not a variant here — it's fully handled (and exits) before
// dispatch ever runs, so a variant for it would be permanently unreachable.
//
// Adding a new subcommand forces a new arm in every exhaustive switch over
// this enum at compile time (missing_enum_constant_in_switch: error).

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
  doctor;

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
        _                => null,
      };
}
