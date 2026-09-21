/// The two named scan-scope values with special meaning. `scanScope` itself
/// stays a plain `String`, not an enum — `scanner.dart` also accepts an
/// arbitrary subdirectory name (e.g. `--scope=test`) as a valid scope, so
/// the domain is open, not closed. These are the only two literals repeated
/// across call sites; a bare custom scope stays inline at its one call site.
abstract final class ScanScope {
  static const lib = 'lib';
  static const full = 'full';
}

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

  const ProjectConfig({
    this.sensitivityMode = false,
    this.scanScope = ScanScope.lib,
    this.scanTrigger = 'on_setup',
    this.diagnosticReporting = false,
    this.lastScan,
    this.projectRoot,
    this.afterFixCommand = 'make rebuild',
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
      };

  ProjectConfig copyWith({
    bool? sensitivityMode,
    String? scanScope,
    String? scanTrigger,
    bool? diagnosticReporting,
    String? lastScan,
    String? projectRoot,
    String? afterFixCommand,
  }) {
    return ProjectConfig(
      sensitivityMode: sensitivityMode ?? this.sensitivityMode,
      scanScope: scanScope ?? this.scanScope,
      scanTrigger: scanTrigger ?? this.scanTrigger,
      diagnosticReporting: diagnosticReporting ?? this.diagnosticReporting,
      lastScan: lastScan ?? this.lastScan,
      projectRoot: projectRoot ?? this.projectRoot,
      afterFixCommand: afterFixCommand ?? this.afterFixCommand,
    );
  }
}
