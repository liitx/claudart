import 'dart:convert';
import 'file_io.dart';
import 'paths.dart';

/// The two named scan-scope values with special meaning. `scanScope` itself
/// stays a plain `String`, not an enum — `scanner.dart` also accepts an
/// arbitrary subdirectory name (e.g. `--scope=test`) as a valid scope, so
/// the domain is open, not closed. These are the only two literals repeated
/// across call sites; a bare custom scope stays inline at its one call site.
abstract final class ScanScope {
  static const lib = 'lib';
  static const full = 'full';
}

/// How long one `claude` pipeline step may run before it is killed (whole
/// process tree) and reported as failed. A generous backstop against a step
/// that never returns (for example a credential helper that hangs), not a
/// performance budget. Override per workspace with `stepTimeoutMinutes` in
/// `config.json`; `0` turns it off.
const Duration defaultStepTimeout = Duration(minutes: 15);

const _defaultAfterFixCommand = 'make rebuild';
const _afterFixCommandKey = 'afterFixCommand';
const _allowedScopeRootsKey = 'allowedScopeRoots';
const _stepTimeoutMinutesKey = 'stepTimeoutMinutes';

/// Project-level persistent config stored as config.json in the workspace.
///
/// `sensitivityMode`/`scanScope`/`scanTrigger`/`diagnosticReporting`/
/// `lastScan`/`projectRoot` used to live here (commit 3bcbd91) alongside a
/// now-superseded config.json-based scan architecture. `scan`'s project
/// root and sensitivity mode moved to the registry (commit 9ac4d81); the
/// old fields were never removed from this type after that migration and
/// had zero real consumers anywhere in lib/ -- confirmed by reading every
/// call site, not inferred. Removed rather than left as dead duplicates of
/// RegistryEntry.sensitivityMode (the real, live flag the sensitivity/
/// obfuscation feature actually reads).
class ProjectConfig {
  /// Shell command run by `claudart rotate` after archiving the current
  /// session, before seeding the next handoff. Must exit 0 to continue.
  /// Defaults to `make rebuild` for self-hosted projects.
  final String afterFixCommand;

  /// Extra directories a `### Files in play` entry may point into besides the
  /// project root itself (for example a sibling package in a monorepo).
  /// Relative entries resolve against the project root. Empty by default, so
  /// a scope path that leaves the project is ignored unless listed here.
  final List<String> allowedScopeRoots;

  /// Per-step timeout in minutes. `null` (key absent) means "use the default"
  /// ([defaultStepTimeout]); an explicit `0` means "no timeout". They are
  /// different states on purpose. See [stepTimeout].
  final int? stepTimeoutMinutes;

  /// The effective per-step timeout: the configured minutes, [defaultStepTimeout]
  /// when unset, or `null` (no limit) when explicitly set to 0.
  Duration? get stepTimeout => switch (stepTimeoutMinutes) {
        null => defaultStepTimeout,
        0 => null,
        final minutes => Duration(minutes: minutes),
      };

  const ProjectConfig({
    this.afterFixCommand = _defaultAfterFixCommand,
    this.allowedScopeRoots = const [],
    this.stepTimeoutMinutes,
  });

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    return ProjectConfig(
      afterFixCommand: json[_afterFixCommandKey] as String? ?? _defaultAfterFixCommand,
      allowedScopeRoots: [
        for (final r in (json[_allowedScopeRootsKey] as List<dynamic>? ?? const []))
          if (r is String && r.trim().isNotEmpty) r.trim(),
      ],
      // Only a non-negative integer counts; anything else (a string, a
      // negative number) is treated as unset rather than guessed at.
      stepTimeoutMinutes: switch (json[_stepTimeoutMinutesKey]) {
        final int minutes when minutes >= 0 => minutes,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        _afterFixCommandKey: afterFixCommand,
        if (allowedScopeRoots.isNotEmpty) _allowedScopeRootsKey: allowedScopeRoots,
        if (stepTimeoutMinutes != null) _stepTimeoutMinutesKey: stepTimeoutMinutes,
      };

  ProjectConfig copyWith({
    String? afterFixCommand,
    List<String>? allowedScopeRoots,
    int? stepTimeoutMinutes,
  }) {
    return ProjectConfig(
      afterFixCommand: afterFixCommand ?? this.afterFixCommand,
      allowedScopeRoots: allowedScopeRoots ?? this.allowedScopeRoots,
      stepTimeoutMinutes: stepTimeoutMinutes ?? this.stepTimeoutMinutes,
    );
  }
}

/// Loads the per-workspace `config.json` (defaults when missing or unreadable).
ProjectConfig loadWorkspaceConfig(String workspace, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final raw = fileIO.read(configPathFor(workspace));
  if (raw.isEmpty) return const ProjectConfig();
  try {
    return ProjectConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on FormatException {
    return const ProjectConfig();
  }
}
