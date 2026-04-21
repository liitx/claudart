/// Single source of truth for the claudart binary version.
///
/// Zedup imports this directly (via the claudart path dependency) so the
/// compile-time constant and the installed binary version can be compared at
/// runtime. When claudart is published to pub.dev, zedup's pubspec constraint
/// (`^X.Y.Z`) enforces the same guarantee statically.
///
/// ∀ feature f added to claudart →
///   claudartVersion is bumped ∧ zedup's minClaudartVersion is updated
///   → dart pub get detects the mismatch before any binary is run.
const claudartVersion = '1.0.0';
