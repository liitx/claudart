// spec_obligations.dart — the stage 3 obligations as data
// (docs/methodical_refactor.md, "Stage 3 - listener design").
//
// The spec says what must hold. It must also say where the runtime reads it,
// which test checks it, and which test shows a weakened version failing, or a
// builder can satisfy the tests and miss the point (gaps T1 to T4). Each
// obligation carries those; `spec_obligations_test.dart` fails when a built
// one is missing any.

/// A test or group, by the file it is in and the title it is called with.
typedef TestRef = ({String file, String title});

enum SpecObligation {
  totality(
    statement: 'Every event is decided: a new event fails to compile until '
        'someone says which reactions it calls for.',
    consultingSymbol: 'listenersFor',
    definedIn: 'lib/session/handoff_listeners.dart',
    consultedUnder: 'lib/',
    check: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'totality',
    ),
    weakened: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'only a fix landing on a finished fix calls for a teardown',
    ),
  ),
  safety(
    statement: 'No reaction may emit an event the status it lands on forbids.',
    consultingSymbol: 'mayEmit',
    definedIn: 'lib/session/handoff_listeners.dart',
    consultedUnder: 'lib/',
    check: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'no listener may emit an event the landing status forbids',
    ),
    weakened: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'the check finds an emission the table forbids',
    ),
  ),
  termination(
    statement: 'The events reactions may emit form no cycle, so a chain is at '
        'most as long as there are events.',
    consultingSymbol: 'mayEmit',
    definedIn: 'lib/session/handoff_listeners.dart',
    consultedUnder: 'lib/',
    check: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'the events listeners may emit form no cycle',
    ),
    weakened: (
      file: 'test/session/handoff_listeners_test.dart',
      title: 'the check finds a cycle',
    ),
  ),
  record(
    statement: 'Each move is one line in transitions.jsonl, written before the '
        'move returns.',
    consultingSymbol: 'recordTransition',
    definedIn: 'lib/session/handoff_listeners.dart',
    consultedUnder: 'lib/',
    check: (
      file: 'test/session/handoff_store_test.dart',
      title: 'apply records the move it made',
    ),
    weakened: (
      file: 'test/session/handoff_store_test.dart',
      title: 'replace of a legal move records it once',
    ),
  ),
  order(
    statement: 'Reactions see moves in the order they were published, and an '
        'event a reaction returns is queued behind the moves already published.',
    consultingSymbol: 'publish',
    definedIn: 'lib/session/transition_bus.dart',
    consultedUnder: 'lib/',
    check: (file: 'test/session/transition_bus_test.dart', title: 'order'),
    weakened: (
      file: 'test/session/transition_bus_test.dart',
      title: 'an event a reaction returns is queued behind moves already '
          'published',
    ),
  ),
  drainCompletes(
    statement: 'drain completes only when every move, and every move a '
        'reaction caused, has been handled.',
    consultingSymbol: 'drain',
    definedIn: 'lib/session/transition_bus.dart',
    consultedUnder: 'lib/',
    check: (file: 'test/session/transition_bus_test.dart', title: 'drain'),
    weakened: (
      file: 'test/session/transition_bus_test.dart',
      title: 'drain completes only when a slow reaction has finished',
    ),
  ),
  isolation(
    statement: 'A subscriber that throws is logged under its failure type and '
        'stops neither the others nor the writer.',
    consultingSymbol: 'logListenerFailure',
    definedIn: 'lib/logging/logger.dart',
    consultedUnder: 'lib/',
    check: (
      file: 'test/session/transition_bus_test.dart',
      title: 'isolation',
    ),
    weakened: (
      file: 'test/session/handoff_store_test.dart',
      title: 'a reaction that throws is logged under its failure type',
    ),
  ),
  everyRunRecorded(
    statement: 'Every command run leaves one row: it returned, it threw, or it '
        'left the process, with how long it took and why when it says.',
    consultingSymbol: 'runRecorded',
    definedIn: 'lib/commands/support/interaction_boundary.dart',
    consultedUnder: 'bin/',
    check: (
      file: 'test/commands/interaction_boundary_test.dart',
      title: 'a command that returns',
    ),
    weakened: (
      file: 'test/commands/interaction_boundary_test.dart',
      title: 'a command that throws',
    ),
  ),
  headlessClosesOnlyOnVerified(
    statement: 'A headless teardown archives and updates what was learned only '
        'when the evidence is verified; anything less is a reminder.',
    consultingSymbol: 'closureEvidenceOf',
    definedIn: 'lib/session/closure_evidence.dart',
    consultedUnder: 'lib/commands/',
    check: (
      file: 'test/commands/teardown_test.dart',
      title: 'teardown — headless closes only on verified evidence',
    ),
    weakened: (
      file: 'test/session/closure_evidence_test.dart',
      title: 'a fix that was applied but not verified is not verified evidence',
    ),
  ),
  commandAwaitsDrain(
    statement: 'A command that attached a reaction awaits drain before it '
        'returns, so no record or reaction is lost at exit.',
    consultingSymbol: 'drain',
    definedIn: 'lib/session/handoff_store.dart',
    consultedUnder: 'lib/commands/',
    check: (
      file: 'test/commands/debug_test.dart',
      title: 'headless: debug returns only after the close has finished',
    ),
    weakened: (
      file: 'test/commands/debug_test.dart',
      title: 'debug has not returned while the close is still running',
    ),
  ),
  commandAttachesReaction(
    statement: 'A headless or flow run attaches teardownWhenConverged, so a '
        'converged, verified session closes itself.',
    consultingSymbol: 'react',
    definedIn: 'lib/session/handoff_store.dart',
    consultedUnder: 'lib/commands/',
    check: (
      file: 'test/commands/debug_test.dart',
      title: 'headless, verified: the session closes itself',
    ),
    weakened: (
      file: 'test/commands/debug_test.dart',
      title: 'interactive, verified: nothing closes the session itself',
    ),
  );

  const SpecObligation({
    required this.statement,
    required this.consultingSymbol,
    required this.definedIn,
    required this.consultedUnder,
    this.check,
    this.weakened,
  });

  /// The property, in one sentence.
  final String statement;

  /// The runtime symbol that reads what the proof is about.
  final String consultingSymbol;

  /// The file that defines [consultingSymbol].
  final String definedIn;

  /// The folder whose code must read [consultingSymbol], outside [definedIn].
  final String consultedUnder;

  /// The test that checks the obligation. Null while it is pending.
  final TestRef? check;

  /// The test that shows a weakened version failing. Null while pending.
  final TestRef? weakened;

  /// Whether the obligation is built: it names its checks. A pending one has
  /// none, and no runtime code reads its symbol yet.
  bool get isBuilt => check != null;
}

/// Whether code under [obligation]'s folder, other than its definition, reads
/// its symbol: the proof is of something the runtime consults.
bool isConsulted(SpecObligation obligation, Map<String, String> sources) {
  final symbol = RegExp(r'\b' + RegExp.escape(obligation.consultingSymbol) + r'\b');
  return sources.entries.any(
    (entry) =>
        entry.key.startsWith(obligation.consultedUnder) &&
        entry.key != obligation.definedIn &&
        symbol.hasMatch(entry.value),
  );
}

/// Whether [ref]'s file calls `test` or `group` with exactly its title.
bool namesTest(Map<String, String> sources, TestRef ref) {
  final text = sources[ref.file];
  if (text == null) return false;
  final title = RegExp.escape(ref.title).replaceAll("'", "\\\\'");
  return RegExp(r"""(?:test|group)\(\s*(['"])""" + title + r'\1').hasMatch(text);
}
