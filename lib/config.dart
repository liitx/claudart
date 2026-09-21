/// Project-level persistent config stored as config.json in the workspace.
class WorkspaceConfig {
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

  const WorkspaceConfig({
    this.sensitivityMode = false,
    this.scanScope = 'lib',
    this.scanTrigger = 'on_setup',
    this.diagnosticReporting = false,
    this.lastScan,
    this.projectRoot,
    this.afterFixCommand = 'make rebuild',
  });

  factory WorkspaceConfig.fromJson(Map<String, dynamic> json) {
    return WorkspaceConfig(
      sensitivityMode: json['sensitivityMode'] as bool? ?? false,
      scanScope: json['scanScope'] as String? ?? 'lib',
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

  WorkspaceConfig copyWith({
    bool? sensitivityMode,
    String? scanScope,
    String? scanTrigger,
    bool? diagnosticReporting,
    String? lastScan,
    String? projectRoot,
    String? afterFixCommand,
  }) {
    return WorkspaceConfig(
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
