import 'dart:convert';
import 'package:path/path.dart' as p;
import 'file_io.dart';
import 'paths.dart';

/// Project-level persistent config stored as config.json in the workspace.
class WorkspaceConfig {
  final bool sensitivityMode;
  final String scanScope;
  final String scanTrigger;
  final bool diagnosticReporting;
  final String? lastScan;
  final String? projectRoot;

  const WorkspaceConfig({
    this.sensitivityMode = false,
    this.scanScope = 'lib',
    this.scanTrigger = 'on_setup',
    this.diagnosticReporting = false,
    this.lastScan,
    this.projectRoot,
  });

  factory WorkspaceConfig.fromJson(Map<String, dynamic> json) {
    return WorkspaceConfig(
      sensitivityMode: json['sensitivityMode'] as bool? ?? false,
      scanScope: json['scanScope'] as String? ?? 'lib',
      scanTrigger: json['scanTrigger'] as String? ?? 'on_setup',
      diagnosticReporting: json['diagnosticReporting'] as bool? ?? false,
      lastScan: json['lastScan'] as String?,
      projectRoot: json['projectRoot'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sensitivityMode': sensitivityMode,
        'scanScope': scanScope,
        'scanTrigger': scanTrigger,
        'diagnosticReporting': diagnosticReporting,
        if (lastScan != null) 'lastScan': lastScan,
        if (projectRoot != null) 'projectRoot': projectRoot,
      };

  WorkspaceConfig copyWith({
    bool? sensitivityMode,
    String? scanScope,
    String? scanTrigger,
    bool? diagnosticReporting,
    String? lastScan,
    String? projectRoot,
  }) {
    return WorkspaceConfig(
      sensitivityMode: sensitivityMode ?? this.sensitivityMode,
      scanScope: scanScope ?? this.scanScope,
      scanTrigger: scanTrigger ?? this.scanTrigger,
      diagnosticReporting: diagnosticReporting ?? this.diagnosticReporting,
      lastScan: lastScan ?? this.lastScan,
      projectRoot: projectRoot ?? this.projectRoot,
    );
  }
}

String get configPath => p.join(claudeDir, 'config.json');

WorkspaceConfig loadConfig({FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final raw = fileIO.read(configPath);
  if (raw.isEmpty) return const WorkspaceConfig();
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WorkspaceConfig.fromJson(json);
  } catch (_) {
    return const WorkspaceConfig();
  }
}

void saveConfig(WorkspaceConfig config, {FileIO? io}) {
  final fileIO = io ?? const RealFileIO();
  final encoder = const JsonEncoder.withIndent('  ');
  fileIO.write(configPath, encoder.convert(config.toJson()));
}
