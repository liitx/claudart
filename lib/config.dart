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

/// Project-level persistent config stored as config.json in the workspace.
class ProjectConfig {
  final bool sensitivityMode;
  final String scanScope;
  final String scanTrigger;
  final bool diagnosticReporting;
  final String? lastScan;
  final String? projectRoot;

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
    this.sensitivityMode = false,
    this.scanScope = ScanScope.lib,
    this.scanTrigger = 'on_setup',
    this.diagnosticReporting = false,
    this.lastScan,
    this.projectRoot,
    this.afterFixCommand = 'make rebuild',
    this.allowedScopeRoots = const [],
    this.stepTimeoutMinutes,
  });

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    return ProjectConfig(
      sensitivityMode: json['sensitivityMode'] as bool? ?? false,
      scanScope: json['scanScope'] as String? ?? ScanScope.lib,
      scanTrigger: json['scanTrigger'] as String? ?? 'on_setup',
      diagnosticReporting: json['diagnosticReporting'] as bool? ?? false,
      lastScan: json['lastScan'] as String?,
      projectRoot: json['projectRoot'] as String?,
      afterFixCommand: json['afterFixCommand'] as String? ?? 'make rebuild',
      allowedScopeRoots: [
        for (final r in (json['allowedScopeRoots'] as List<dynamic>? ?? const []))
          if (r is String && r.trim().isNotEmpty) r.trim(),
      ],
      // Only a non-negative integer counts; anything else (a string, a
      // negative number) is treated as unset rather than guessed at.
      stepTimeoutMinutes: switch (json['stepTimeoutMinutes']) {
        final int minutes when minutes >= 0 => minutes,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'sensitivityMode': sensitivityMode,
        'scanScope': scanScope,
        'scanTrigger': scanTrigger,
        'diagnosticReporting': diagnosticReporting,
        if (lastScan != null) 'lastScan': lastScan,
        if (projectRoot != null) 'projectRoot': projectRoot,
        'afterFixCommand': afterFixCommand,
        if (allowedScopeRoots.isNotEmpty) 'allowedScopeRoots': allowedScopeRoots,
        if (stepTimeoutMinutes != null) 'stepTimeoutMinutes': stepTimeoutMinutes,
      };

  ProjectConfig copyWith({
    bool? sensitivityMode,
    String? scanScope,
    String? scanTrigger,
    bool? diagnosticReporting,
    String? lastScan,
    String? projectRoot,
    String? afterFixCommand,
    List<String>? allowedScopeRoots,
    int? stepTimeoutMinutes,
  }) {
    return ProjectConfig(
      sensitivityMode: sensitivityMode ?? this.sensitivityMode,
      scanScope: scanScope ?? this.scanScope,
      scanTrigger: scanTrigger ?? this.scanTrigger,
      diagnosticReporting: diagnosticReporting ?? this.diagnosticReporting,
      lastScan: lastScan ?? this.lastScan,
      projectRoot: projectRoot ?? this.projectRoot,
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
