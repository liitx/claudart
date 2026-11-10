// fault.dart — what the proof audit seeds, and the checks that must see it
//
// A proof (or a matrix that decides which tests run) is trusted only if it
// fails when the thing it covers is wrong. A [FaultProvider] names one such
// subject, the tests that check it in two tiers, and every single fault worth
// seeding; the runner seeds each in a scratch copy and logs whether the tests
// saw it. A new matrix is audited by adding a provider, not by changing the
// runner.

/// One seeded defect: where it stands in the source and how to apply it.
abstract class SeededFault {
  const SeededFault();

  /// The proof or matrix this fault is seeded against.
  String get proof;

  /// What was changed, in words the report can show.
  String get description;

  /// The source file, relative to the repository root, the fault changes.
  String get sourceFile;

  /// The line of that file the fault stands for in the unchanged source.
  int get sourceLine;

  /// The text of [sourceFile] with the fault in place.
  String apply(String source);
}

/// A subject of the audit: the tests that check it and every fault to seed.
abstract class FaultProvider {
  const FaultProvider();

  /// The proof or matrix name, as the log records it.
  String get proof;

  /// The tests that are meant to carry the proof: run first, fast.
  List<String> get tierOneTests;

  /// A wider set run only for a fault tier one missed, so a gap in the named
  /// proofs is told apart from a gap in the whole suite.
  List<String> get tierTwoTests;

  /// Every fault, in a fixed order, built from the unchanged source.
  List<SeededFault> faults(String repositoryRoot);
}
