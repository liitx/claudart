// controls.dart — faults whose verdict is known, run before the real ones
//
// An audit that only ever says "caught" proves nothing about its own eyes. A
// change that alters no behavior must come out `missed`, and source that does
// not compile must come out `invalid`; if either does not, the runner cannot be
// trusted and the audit stops before it seeds a real fault.

import 'package:claudart/logging/logger.dart';

import 'fault.dart';

/// The file the controls change when none is given.
const defaultControlFile = 'lib/session/session_state.dart';

/// The proof name the control faults are logged under.
const controlProof = 'control';

/// A fault and the verdict the runner must give it.
class Control {
  const Control(this.fault, this.expected);

  final SeededFault fault;
  final ProofVerdict expected;
}

class _NoBehaviorChange extends SeededFault {
  const _NoBehaviorChange(this.sourceFile);

  @override
  final String sourceFile;

  @override
  String get proof => controlProof;

  @override
  String get description => 'control: a comment appended, no behavior changed';

  @override
  int get sourceLine => 1;

  @override
  String apply(String source) => '$source\n// a comment changes nothing\n';
}

class _DoesNotCompile extends SeededFault {
  const _DoesNotCompile(this.sourceFile);

  @override
  final String sourceFile;

  @override
  String get proof => controlProof;

  @override
  String get description => 'control: source that does not compile';

  @override
  int get sourceLine => 1;

  @override
  String apply(String source) => '$source\nthis is not dart;\n';
}

/// The controls, changing [file].
List<Control> controlsFor(String file) => [
      Control(_NoBehaviorChange(file), ProofVerdict.missed),
      Control(_DoesNotCompile(file), ProofVerdict.invalid),
    ];
