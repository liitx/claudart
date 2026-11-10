// controls.dart — faults whose verdict is known, run before the real ones
//
// An audit that only ever says "caught" proves nothing about its own eyes. A
// change that alters no behavior must come out `missed`, and source that does
// not compile must come out `invalid`; if either does not, the runner cannot be
// trusted and the audit stops before it seeds a real fault.

import 'package:claudart/logging/logger.dart';

import 'fault.dart';

const _sourceFilePath = 'lib/session/session_state.dart';

/// A fault and the verdict the runner must give it.
class Control {
  const Control(this.fault, this.expected);

  final SeededFault fault;
  final ProofVerdict expected;
}

class _NoBehaviorChange extends SeededFault {
  const _NoBehaviorChange();

  @override
  String get proof => 'control';

  @override
  String get description => 'control: a comment appended, no behavior changed';

  @override
  String get sourceFile => _sourceFilePath;

  @override
  int get sourceLine => 1;

  @override
  String apply(String source) => '$source\n// a comment changes nothing\n';
}

class _DoesNotCompile extends SeededFault {
  const _DoesNotCompile();

  @override
  String get proof => 'control';

  @override
  String get description => 'control: source that does not compile';

  @override
  String get sourceFile => _sourceFilePath;

  @override
  int get sourceLine => 1;

  @override
  String apply(String source) => '$source\nthis is not dart;\n';
}

const controls = <Control>[
  Control(_NoBehaviorChange(), ProofVerdict.missed),
  Control(_DoesNotCompile(), ProofVerdict.invalid),
];
